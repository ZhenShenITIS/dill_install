#!/bin/bash

# Проверка и установка Docker
command -v docker >/dev/null 2>&1 || { echo "Docker не установлен. Устанавливаю Docker..."; apt-get update && apt-get install -y docker.io; }

# Функция для поиска блока свободных портов
find_free_port_block() {
    local start_port=$1
    local num_ports=$2
    local increment=$3
    local max_port=65535  # Максимальный номер порта

    while [ $start_port -le $((max_port - num_ports)) ]; do
        local all_free=true
        for ((port=$start_port; port<$((start_port + num_ports)); port++)); do
            if netstat -tuln | grep -q ":${port}[[:space:]]"; then
                all_free=false
                break
            fi
        done
        if [ "$all_free" = true ]; then
            echo "$start_port"
            return 0
        else
            start_port=$((start_port + increment))
        fi
    done
    return 1  # Не удалось найти свободный блок портов
}

# Функция для запуска контейнера с программой DillLabs
run_dill_container() {
    local instance_num=$1
    local proxy_info=$2
    local instance_name="dill_instance$instance_num"
    local instance_dir="/root/dill_instances/instance$instance_num"

    # Создаем директорию экземпляра
    mkdir -p "$instance_dir"

    # Сохраняем proxy_info в файл для будущего использования
    echo "$proxy_info" > "$instance_dir/proxy.conf"

    # Парсим proxy_info
    PROXY_IP=$(echo $proxy_info | cut -d':' -f1)
    PROXY_PORT=$(echo $proxy_info | cut -d':' -f2)
    PROXY_USER=$(echo $proxy_info | cut -d':' -f3)
    PROXY_PASS=$(echo $proxy_info | cut -d':' -f4)

    # Копируем архив программы в директорию экземпляра
    cp "dill-v1.0.3-linux-amd64.tar.gz" "$instance_dir/"

    # Создаем Dockerfile в директории экземпляра
    cat > "$instance_dir/Dockerfile" <<EOF
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Настройка HTTP прокси
ENV http_proxy="http://$PROXY_USER:$PROXY_PASS@$PROXY_IP:$PROXY_PORT/"
ENV https_proxy="http://$PROXY_USER:$PROXY_PASS@$PROXY_IP:$PROXY_PORT/"

# Установка необходимых пакетов
RUN apt-get update && apt-get install -y curl expect net-tools lsof

# Создание и установка рабочего каталога
RUN mkdir /dill
WORKDIR /dill

# Копирование архива программы в контейнер
COPY dill-v1.0.3-linux-amd64.tar.gz /dill/

RUN chmod 777 dill-v1.0.3-linux-amd64.tar.gz

# Загрузка dill.sh
RUN curl -sO https://raw.githubusercontent.com/ZhenShenITIS/dillofficial/refs/heads/main/dill.sh && chmod +x dill.sh

# Удержание контейнера запущенным
CMD ["tail", "-f", "/dev/null"]
EOF

    # Собираем Docker образ для данного экземпляра
    docker build -t dill_image_$instance_num "$instance_dir"

    # Расчет порта
    base_port=30000
    num_ports=9
    increment=9
    initial_start_port=$((base_port + (instance_num - 1) * increment))
    start_port=$(find_free_port_block $initial_start_port $num_ports $increment)
    if [ $? -ne 0 ]; then
        echo "Не удалось найти свободный блок из $num_ports портов начиная с порта $initial_start_port"
        exit 1
    fi
    end_port=$((start_port + num_ports - 1))

    PORTS_MAPPING=""
    for ((port=$start_port; port<=$end_port; port++)); do
        PORTS_MAPPING="$PORTS_MAPPING -p $port:$port"
    done

    # Выводим занимаемые порты перед запуском контейнера
    echo "Экземпляр $instance_name использует порты с $start_port по $end_port:"
    for ((port=$start_port; port<=$end_port; port++)); do
        echo "Хостовый порт $port -> Порт контейнера $port"
    done

    # Запускаем контейнер
    docker run -d $PORTS_MAPPING --name $instance_name dill_image_$instance_num

    # Переходим в контейнер
    docker exec -it $instance_name /bin/bash
}

# Функция для копирования validator_keys из контейнеров
copy_validator_keys() {
    base_dir="/root/dill_instances"

    # Находим все контейнеры с именем dill_instanceN
    for container in $(docker ps -a --filter "name=dill_instance" --format "{{.Names}}"); do
        echo "Копирование validator_keys из контейнера $container..."

        # Получаем номер экземпляра из имени контейнера
        instance_num=$(echo $container | grep -o '[0-9]\+')
        instance_dir="$base_dir/instance$instance_num"

        # Проверяем, существует ли директория назначения
        if [ ! -d "$instance_dir" ]; then
            echo "Директория $instance_dir не существует, создаю..."
            mkdir -p "$instance_dir"
        fi

        # Проверяем, существует ли директория validator_keys внутри контейнера
        if docker exec "$container" [ -d "/dill/dill/validator_keys" ]; then
            # Копируем директорию
            docker cp "$container":/dill/dill/validator_keys "$instance_dir"/validator_keys

            if [ $? -eq 0 ]; then
                echo "validator_keys успешно скопирован в $instance_dir/validator_keys"
            else
                echo "Ошибка при копировании validator_keys из контейнера $container"
            fi
        else
            echo "Директория /dill/dill/validator_keys не найдена в контейнере $container"
        fi
    done
}

# Основное меню
while true; do
    echo ""
    echo "█▀▀ █▄▄ █▀▀ █▀▄▀█   █▀▄ █ █   █  "
    echo "██▄ █▄█ ██▄ █ ▀ █   █▄▀ █ █▄▄ █▄▄"
    echo " by @ZhenShen9 and begunki uzlov "
    echo ""
    echo "Выберите действие:"
    echo "1. Установить новую ноду"
    echo "2. Сделать бэкап папок с ключами"
    echo "0. Выход"
    read -p "Введите номер действия: " action

    case $action in
        1)
            echo "Установка новой ноды..."

            # Запрос данных у пользователя
            read -p "Введите данные HTTP прокси (IP:Port:Login:Pass): " proxy_details

            # Получаем номер следующего экземпляра
            base_dir="/root/dill_instances"
            if [ ! -d "$base_dir" ]; then
                mkdir -p "$base_dir"
            fi
            instance_num=$(ls -l $base_dir | grep -c ^d)
            instance_num=$((instance_num + 1))

            # Запускаем контейнер с программой
            run_dill_container $instance_num "$proxy_details"

            ;;
        2)
            copy_validator_keys
            ;;
        0)
            echo "Выход."
            exit 0
            ;;
        *)
            echo "Неверный выбор. Попробуйте снова."
            ;;
    esac
done

#!/bin/bash

# Проверка и установка Docker
command -v docker >/dev/null 2>&1 || { echo "Docker не установлен. Устанавливаю Docker..."; apt-get update && apt-get install -y docker.io; }

# Функция для поиска блока свободных портов
find_free_ports() {
    local start_port=$1
    local count=$2
    local ports=()
    local port=$start_port
    while [ ${#ports[@]} -lt $count ]; do
        if ! netstat -tuln | grep -q ":$port "; then
            ports+=($port)
        fi
        port=$((port + 1))
    done
    echo "${ports[@]}"
}

# Функция для запуска контейнера с программой DillLabs
run_dill_container() {
    local instance_num=$1
    local proxy_info=$2
    shift 2
    local ports=("$@")
    local instance_name="dill_instance$instance_num"
    local instance_dir="/root/dill_instances/instance$instance_num"

    # Создаем директорию экземпляра
    mkdir -p "$instance_dir"

    # Сохраняем proxy_info и ports в файлы для будущего использования
    echo "$proxy_info" > "$instance_dir/proxy.conf"
    echo "${ports[@]}" > "$instance_dir/ports.conf"

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

    # Необходимые порты контейнера
    REQUIRED_PORTS=(8080 3500 4000 8082 13000 8551 8545 30303)

    # Создаем строку с отображением портов
    PORTS_MAPPING=""
    for i in "${!ports[@]}"; do
        HOST_PORT=${ports[$i]}
        CONTAINER_PORT=${REQUIRED_PORTS[$i]}
        PORTS_MAPPING="$PORTS_MAPPING -p $HOST_PORT:$CONTAINER_PORT"
    done

    # Запускаем контейнер
    docker run -d $PORTS_MAPPING --name $instance_name dill_image_$instance_num
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

            # Получаем свободные порты
            REQUIRED_PORTS=(8080 3500 4000 8082 13000 8551 8545 30303)
            ports_needed=${#REQUIRED_PORTS[@]}
            free_ports=($(find_free_ports 30000 $ports_needed))

            # Запускаем контейнер с программой
            run_dill_container $instance_num "$proxy_details" "${free_ports[@]}"

            # Объединяем порты в строку для вывода
            ports_list=$(printf '%s ' "${free_ports[@]}")
            echo "Экземпляр dill_instance$instance_num успешно запущен с портами $ports_list"
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

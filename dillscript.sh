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
RUN curl -sO https://raw.githubusercontent.com/DillLabs/launch-dill-node/main/dill.sh && chmod +x dill.sh

# Удержание контейнера запущенным
CMD ["tail", "-f", "/dev/null"]
EOF
## Копирование скрипта автоматизации
#COPY automate_dill.sh /dill/automate_dill.sh
#RUN chmod +x /dill/automate_dill.sh
#
## Запуск скрипта при запуске контейнера
#CMD ["/dill/automate_dill.sh"]



    # Создаем скрипт автоматизации automate_dill.sh
#    cat > "$instance_dir/automate_dill.sh" <<'EOF'
##!/usr/bin/expect -f
#
#set timeout -1
#
#spawn /dill/dill.sh
#
## Автоматизация интерактивного меню
## Измените следующие команды в соответствии с вашими потребностями
## Пример:
## expect "Enter option: " { send "1\r" }
## Добавьте дополнительные expect-send пары по мере необходимости
#
#expect eof
#EOF

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

# Основное меню
while true; do
    echo ""
    echo "█▀▀ █▄▄ █▀▀ █▀▄▀█   █▀▄ █ █   █  "
    echo "██▄ █▄█ ██▄ █ ▀ █   █▄▀ █ █▄▄ █▄▄"
    echo " by @ZhenShen9 and begunki uzlov "
    echo ""
    echo "Выберите действие:"
    echo "1. Установить новую ноду"
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
        0)
            echo "Выход."
            exit 0
            ;;
        *)
            echo "Неверный выбор. Попробуйте снова."
            ;;
    esac
done

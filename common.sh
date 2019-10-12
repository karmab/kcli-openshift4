
# set some printing colors
RED='\033[0;31m'
BLUE='\033[0;36m'
NC='\033[0m'

if [ -d /Users ] ; then
    SYSTEM=macosx
    INSTALLSYSTEM=mac
    jq=jq-1.6/jq-osx-amd64
    BASE64D="base64 -D"
else
    SYSTEM=linux
    INSTALLSYSTEM=linux
    jq=jq-1.6/jqlinux64
    BASE64D="base64 -d"
fi
export PATH=.:$PATH

which -s kcli
BIN="$?"
alias kcli >/dev/null 2>&1
ALIAS="$?"

if [ "$BIN" != "0" ] && [ "$ALIAS" != "0" ]; then
  engine="docker"
  which -s podman && engine="podman"
  VOLUMES=""
  [ -d /var/lib/libvirt/images ] && [ -d /var/run/libvirt ] && VOLUMES="-v /var/lib/libvirt/images:/var/lib/libvirt/images -v /var/run/libvirt:/var/run/libvirt"
  [ -d $HOME/.kcli ] || mkdir -p $HOME/.kcli
  alias kcli="$engine run --net host -it --rm --security-opt label=disable -v $HOME/.kcli:/root/.kcli $VOLUMES -v $PWD:/workdir -v /var/tmp:/ignitiondir karmab/kcli"
  echo -e "${BLUE}Using $(alias kcli)${NC}"
fi

shopt -s expand_aliases
kcli -v >/dev/null 2>&1
if [ "$?" != "0" ] ; then
  echo -e "${RED}kcli not found. Install it from copr karmab/kcli or pull container${NC}"
  exit 1
fi

#!/bin/sh
# بديل خفيف لأوامر Termux (pkg / termux-wake-lock) التي تستدعيها الأداة على أنظمة posix
case "$(basename "$0")" in
  pkg) [ "$1" = "list-installed" ] && echo "openjdk-17 aapt2 radare2" ;;
esac
exit 0

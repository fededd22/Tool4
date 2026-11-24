FROM python:3.13-slim-trixie

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TERM=xterm \
    DATA_DIR=/data \
    APKPATCHER_TOOLS_DIR=/opt/apkpatcher-tools \
    APKPATCHER_DESKTOP_APKTOOL=1 \
    APKPATCHER_NO_UPDATE=1

# Java مطلوب لـ APKTool / APKEditor / ApkSig، و radare2 لباتش Flutter فقط
RUN apt-get update \
 && apt-get install -y --no-install-recommends default-jre-headless ca-certificates \
 && (apt-get install -y --no-install-recommends radare2 || echo "radare2 غير متوفر: باتش Flutter لن يعمل") \
 && rm -rf /var/lib/apt/lists/* \
 # الأداة تستدعي الأمر باسمين مختلفين (radare2 في Scan.py، و r2 في Flutter_SSL_Patch.py).
 # نضمن توفر الاسمين معاً مهما كان اسم الملف التنفيذي الذي ثبّتته الحزمة.
 && if command -v radare2 >/dev/null && ! command -v r2 >/dev/null; then \
      ln -s "$(command -v radare2)" /usr/local/bin/r2; \
    elif command -v r2 >/dev/null && ! command -v radare2 >/dev/null; then \
      ln -s "$(command -v r2)" /usr/local/bin/radare2; \
    fi

# بدائل أوامر Termux التي تستدعيها الأداة
COPY docker/termux-stub.sh /usr/local/bin/pkg
RUN chmod +x /usr/local/bin/pkg \
 && ln -s /usr/local/bin/pkg /usr/local/bin/termux-wake-lock \
 && ln -s /usr/local/bin/pkg /usr/local/bin/termux-wake-unlock

WORKDIR /src
COPY . /src
RUN pip install --no-cache-dir . -r webui/requirements.txt

# تنزيل أدوات الجافا (APKTool / APKEditor / ApkSig) أثناء البناء.
# لا نتجاهل الفشل هنا: لو تعذّر التنزيل يجب أن يفشل البناء بوضوح بدل
# أن تفشل المعالجة لاحقاً بخطأ غامض بسبب ملف jar ناقص أو فارغ.
RUN python -c "from ApkPatcher.Utils.Files_Check import FileCheck; f=FileCheck(); f.Set_Path(); f.isEmulator(); f.F_D(); f.F_D_A()" \
 && echo "== جار التحقق من ملفات الأدوات ==" \
 && find /opt/apkpatcher-tools -type f -printf '%10s  %p\n' \
 && for f in /opt/apkpatcher-tools/APKEditor.jar /opt/apkpatcher-tools/APKTool.jar /opt/apkpatcher-tools/ApkSig.jar; do \
      test -s "$f" || { echo "ملف مفقود أو فارغ: $f"; exit 1; }; \
    done

RUN useradd -m -u 10001 app \
 && mkdir -p /data \
 && chown -R app:app /data /opt/apkpatcher-tools \
 && chown -R app:app "$(python -c 'import ApkPatcher,os;print(os.path.dirname(ApkPatcher.__file__))')"

WORKDIR /src/webui
USER 10001
VOLUME /data
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/healthz')" || exit 1

# عامل واحد فقط (الحالة محفوظة في الذاكرة) مع عدة threads
CMD ["gunicorn", "-w", "1", "--threads", "8", "--timeout", "0", "-b", "0.0.0.0:8000", "app:app"]

# JobHistory Server

Этот сервер хранит историю законченных MapReduce-заданий. Он установлен на `team-39-en`, работает от пользователя `mapred` и использует порты `10020` для RPC и `19888` для веб-интерфейса.

Сначала должен работать HDFS и два NodeManager. Затем на edge можно выполнить:

```bash
cd ~/hdfs-team39
bash scripts/deploy-history.sh
bash scripts/check-history.sh
```

Скрипт добавляет нужные настройки в `mapred-site.xml`, создаёт служебные каталоги в HDFS и запускает systemd-службу. Перед правкой файла он сохраняет копию `.before-history.bak`. NameNode и DataNode он не перезапускает.

Мы уже проверили этот этап на `team-39`: JobHistory возвращает JSON с версией Hadoop 3.4.0, а `check-history.sh` печатает `PASS`.

Если проверка не проходит:

```bash
sudo systemctl status mapreduce-historyserver --no-pager
sudo journalctl -u mapreduce-historyserver -n 80 --no-pager
curl --max-time 10 http://10.39.0.10:19888/ws/v1/history/info
```

Если сервер слушает `127.0.1.1`, проверь, как разрешается имя `team-39-en` в `/etc/hosts`. На нашем стенде именно это мешало подключению по внутреннему IP.

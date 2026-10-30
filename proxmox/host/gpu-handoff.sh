#!/bin/bash
# GPU custody for GTX 1660 (02:00): gpu-debian 1010 <-> windows 1230
KEEPER=1010; GAMER=1230
FLAG=/run/gpu-handoff.inprogress
log() { logger -t gpu-handoff "$*"; }
status() { qm status "$1" 2>/dev/null | awk '{print $2}'; }
host_stopping() { [ "$(systemctl is-system-running 2>/dev/null)" = "stopping" ]; }
claiming() { [ -n "$(find "$FLAG" -mmin -3 2>/dev/null)" ]; }

vmid="$1"; phase="$2"
case "$vmid:$phase" in
  "$GAMER:pre-start")
    touch "$FLAG"
    if [ "$(status $KEEPER)" = "running" ]; then
      log "Windows starting: shutting down gpu-debian"
      if ! qm shutdown $KEEPER --timeout 90 --forceStop 1; then
        log "could not stop gpu-debian, aborting Windows start"
        rm -f "$FLAG"; exit 1
      fi
    fi ;;
  "$GAMER:post-start")
    rm -f "$FLAG" ;;
  "$GAMER:post-stop")
    rm -f "$FLAG"
    if host_stopping; then log "host stopping, not restarting gpu-debian"; exit 0; fi
    log "Windows stopped: handing GPU back to gpu-debian"
    systemd-run --collect --quiet /bin/sh -c "sleep 5; qm start $KEEPER" ;;
  "$KEEPER:pre-start")
    if [ "$(status $GAMER)" = "running" ] || claiming; then
      log "Windows holds or is claiming the GPU, refusing gpu-debian start"
      exit 1
    fi ;;
esac
exit 0

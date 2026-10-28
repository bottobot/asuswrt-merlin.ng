# Task 3A: disable_infosvr nvram guard

Commit 3151f6c02b "rc: add disable_infosvr nvram guard to start_infosvr and infosvr_check", pushed to ap-stripdown. CI run id **40700438258** (in_progress; not waited on).

Start paths: `grep -rn infosvr release/src/router/rc/*.c *.h` shows the only spawn of /usr/sbin/infosvr is start_infosvr() (services.c); its callers are services.c:12661 (start_misc) and watchdog.c infosvr_check() (called at watchdog.c:11652). No other path execs it; nothing else guarded. stop_infosvr() is defined just above start_infosvr() in services.c and prototyped in rc.h:2905, so no header change. nvram_match is already used in both files.

Not compiled (no real build in sandbox); diff re-read: braces balanced, signatures unchanged. The existing RTCONFIG_MODEM_BRIDGE block is kept; guard sits after it.

## Diff
```diff
diff --git a/release/src/router/rc/services.c b/release/src/router/rc/services.c
index ed99a19bcf..8506af09ca 100644
--- a/release/src/router/rc/services.c
+++ b/release/src/router/rc/services.c
@@ -4609,6 +4609,11 @@ start_infosvr()
 		return 0;
 #endif
 
+	if (nvram_match("disable_infosvr", "1")) {
+		stop_infosvr();
+		return 0;
+	}
+
 	return _eval(infosvr_argv, NULL, 0, &pid);
 }
 
diff --git a/release/src/router/rc/watchdog.c b/release/src/router/rc/watchdog.c
index e4d5712bf5..d46c6eb2dd 100644
--- a/release/src/router/rc/watchdog.c
+++ b/release/src/router/rc/watchdog.c
@@ -11116,6 +11116,8 @@ void feedback_check(void)
 
 void infosvr_check(void)
 {
+	if (nvram_match("disable_infosvr", "1"))
+		return;
 	if (!pids("infosvr"))
 		start_infosvr();
 }
```

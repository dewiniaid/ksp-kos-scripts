RUN ONCE kinstall.
LOCAL oldipu IS CONFIG:IPU.
SET CONFIG:IPU TO KINSTALL_CONFIG["IPU"].

PRINT "Starting KINSTALL test mode.".

kinstall("kinstall").

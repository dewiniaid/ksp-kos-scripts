@LAZYGLOBAL OFF. GLOBAL KINSTALL_CONFIG IS LEXICON("fileref",true,"compile",true,"inplace",false,"rewrite",true,"ksm_as_ks",false,"ks_as_ksm",false,"ipu",9999,"minify",true,"comments",true,"lines",-1,"space",-1,"sanity",true,"cleanup",true).FUNCTION KINSTALL_STATUS{PARAMETER msg IS"".PARAMETER status IS"".PARAMETER status_width IS 10.IF msg=""{PRINT"":PADRIGHT(Terminal:Width)AT(0,0).RETURN.}IF status=""{PRINT"["+"":PADRIGHT(status_width):replace(" ","-")+"] "+msg AT(0,0).}ELSE{IF status:length>status_width{SET status TO status:substring(0,status_width).}ELSE{SET status TO status:PADRIGHT(status_width).}PRINT"["+status+"] "+msg AT(0,0).}}FUNCTION KINSTALL_LOG{PARAMETER func. PARAMETER sev. PARAMETER msg. LOCAL usehud IS false. LOCAL hudcolor IS red. IF sev="fatal"OR sev="error"OR SEV="warning"{SET sev TO sev:toupper.}LOCAL msg IS func+"["+sev+"]: "+msg. PRINT"*** "+msg. IF usehud{HUDTEXT(msg,5,2,15,hudcolor,false).KINSTALL_STATUS(msg).}}

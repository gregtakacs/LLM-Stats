"""Reference probe for the h3-3 browser front (run by the slice lead, 2026-11-14; not a test).

Proves, in Chrome headless: a page at https://hub.example.com (served over plain http on a free
port via Fetch.continueRequest url rewriting) gets a genuine Origin, per-host cookies from a jar
the front owns, frames https://code.example.com through X-Frame-Options SAMEORIGIN + frame-ancestors,
and receives a postMessage from the frame. Continuing a GET with its own echoed headers works when
a reader thread answers every Fetch.requestPaused (no event is dropped while waiting for replies).
Output seen: ["https://hub.example.com",["https://code.example.com {project}-renewed"],1] and every
request carrying the jar cookie of its own host."""
import sys, json, threading, time, tempfile, subprocess, http.client
import os; sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from hub.tests import test_h2_browser as h2b
from hub.tests import httputil
seen=[]
class H(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def _do(self):
        n=int(self.headers.get("Content-Length") or 0); self.rfile.read(n)
        seen.append((self.command,self.path,self.headers.get("Host"),self.headers.get("Origin"),self.headers.get("Cookie")))
        host=self.headers.get("Host","").split(":")[0]
        extra=[]
        if self.path.startswith("/frame"):
            body=b"<p>framed</p><script src='/msg.js'></script>"; extra=[("X-Frame-Options","SAMEORIGIN"),("Content-Security-Policy","frame-ancestors 'self' https://hub.example.com")]
        elif self.path=="/msg.js":
            body=b"parent.postMessage('{project}-renewed','https://hub.example.com');"
        elif host=="hub.example.com" and self.path=="/":
            body=b"<html><body>hub<script src='/main.js'></script></body></html>"
        elif self.path=="/main.js":
            body=b"window.got=[];addEventListener('message',e=>window.got.push(e.origin+' '+e.data));var f=document.createElement('iframe');f.src='https://code.example.com/frame';document.body.appendChild(f);fetch('/post',{method:'POST',body:'x'});"
        elif self.path=="/redir":
            self.send_response(302); self.send_header("Location","https://code.example.com/frame"); self.send_header("Content-Length","0"); self.end_headers(); return
        else:
            body=b"ok"
        self.send_response(200); self.send_header("Content-Type","text/javascript" if self.path.endswith(".js") else "text/html")
        for k,v in extra: self.send_header(k,v)
        self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    do_GET=do_POST=_do
    def log_message(self,*a): pass
srv=ThreadingHTTPServer(("127.0.0.1",0),H); port=srv.server_address[1]
threading.Thread(target=srv.serve_forever,daemon=True).start()
prof=tempfile.mkdtemp(); dport=httputil.free_port()
proc=subprocess.Popen([h2b.CHROME,"--headless=new","--no-sandbox","--disable-gpu","--no-first-run",f"--remote-debugging-port={dport}",f"--user-data-dir={prof}","--host-resolver-rules=MAP hub.example.com 127.0.0.1, MAP code.example.com 127.0.0.1","about:blank"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
for _ in range(100):
    try:
        c=http.client.HTTPConnection("127.0.0.1",dport,timeout=2);c.request("GET","/json");t=[x for x in json.loads(c.getresponse().read()) if x.get("type")=="page"]
        if t: break
    except OSError: pass
    time.sleep(0.2)
dt=h2b.DevTools(t[0]["webSocketDebuggerUrl"])
jar={"hub.example.com":"c=v","code.example.com":"c2=w"}
lock=threading.Lock(); replies={}; cv=threading.Condition()
nid=[1000]
def send(method,params):
    with lock:
        nid[0]+=1; i=nid[0]; dt._send(json.dumps({"id":i,"method":method,"params":params}).encode()); return i
def reader():
    while True:
        try: m=dt._read_message()
        except Exception: return
        if m.get("method")=="Fetch.requestPaused":
            p=m["params"]; u=p["request"]["url"]; host=u.split("/")[2]
            new=u.replace("https://"+host, f"http://{host}:{port}",1)
            hd=[{"name":k,"value":v} for k,v in p["request"]["headers"].items() if k.lower()!="cookie"]
            if host in jar: hd.append({"name":"Cookie","value":jar[host]})
            send("Fetch.continueRequest",{"requestId":p["requestId"],"url":new,"headers":hd})
        elif "id" in m:
            with cv: replies[m["id"]]=m; cv.notify_all()
threading.Thread(target=reader,daemon=True).start()
def cmd(method,**params):
    i=send(method,params)
    with cv:
        cv.wait_for(lambda: i in replies, timeout=20)
        return replies.pop(i)
cmd("Page.enable")
cmd("Fetch.enable",patterns=[{"urlPattern":"https://*","requestStage":"Request"}])
cmd("Page.navigate",url="https://hub.example.com/")
time.sleep(4)
print(cmd("Runtime.evaluate",expression="JSON.stringify([location.origin, window.got, frames.length])",returnByValue=True)["result"]["result"]["value"])
for s in seen: print(s)
proc.kill()

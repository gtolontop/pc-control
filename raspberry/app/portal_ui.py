"""GTOL PC Control — interface PWA sobre, rapide, mobile-first.

Cinq onglets (Accueil, Écran, Fichiers, Système, Terminal). Le flux d'écran passe
par le canal direct de l'agent : trames dédupliquées, curseur dessiné et interpolé
côté client, entrées quasi instantanées. Toutes les actions passent par une liste
blanche stricte côté serveur.
"""

STYLE = r"""
*,*::before,*::after{box-sizing:border-box}
:root{
  color-scheme:dark;
  /* Surfaces */
  --bg:#0a0a0c;--surface:#141418;--raised:#1b1b20;--line:#26262d;--edge:#33333c;
  /* Texte */
  --text:#f2f2f0;--dim:#9b9ba4;--faint:#6b6b75;--inverse:#0a0a0c;
  /* États */
  --ok:#4ade80;--warn:#f0b849;--bad:#f2705c;--accent:#7c9cff;
  /* Échelle d'espacement : une seule source de vérité */
  --s1:4px;--s2:8px;--s3:12px;--s4:16px;--s5:20px;--s6:28px;
  --r:16px;--ri:12px;--rs:9px;--nav:60px;
  font-family:ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,system-ui,sans-serif;
  -webkit-tap-highlight-color:transparent
}
.mono,.val,.crumb,.term,.badge,.fps{font-family:ui-monospace,"SF Mono",SFMono-Regular,Consolas,"Liberation Mono",monospace;font-variant-numeric:tabular-nums;font-feature-settings:"tnum"}
html{background:var(--bg);-webkit-text-size-adjust:100%}
body{margin:0;min-height:100dvh;background:var(--bg);color:var(--text);font-size:14px;line-height:1.45;-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;overscroll-behavior-y:none}
button,input,textarea,select{font:inherit;color:inherit}
[hidden]{display:none!important}
::selection{background:var(--text);color:var(--inverse)}
button{cursor:pointer;border:0;background:none;padding:0;color:inherit}
button:disabled{opacity:.35;cursor:not-allowed}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px}
::-webkit-scrollbar{width:8px;height:8px}
::-webkit-scrollbar-thumb{background:var(--edge);border-radius:4px}
::-webkit-scrollbar-track{background:transparent}

/* ---------- Structure ---------- */
.app{width:min(100%,760px);margin-inline:auto;padding:0 var(--s3) calc(var(--nav) + var(--s6) + env(safe-area-inset-bottom))}

/* En-tête collant, aligné sur la grille de la page */
.top{position:sticky;top:0;z-index:30;display:flex;align-items:center;justify-content:space-between;gap:var(--s3);
  height:56px;margin-bottom:var(--s3);padding-top:env(safe-area-inset-top);
  background:linear-gradient(var(--bg) 62%,rgba(10,10,12,0));backdrop-filter:blur(10px)}
.brand{display:flex;align-items:center;gap:10px;min-width:0}
.logo{display:grid;width:32px;height:32px;flex:none;place-items:center;border-radius:10px;background:var(--text);color:var(--inverse);font-size:11px;font-weight:800;letter-spacing:.02em}
.brand-txt{min-width:0;display:flex;flex-direction:column;justify-content:center;gap:1px}
.brand-txt b{font-size:14px;font-weight:650;letter-spacing:-.01em;line-height:1.15;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.brand-txt small{color:var(--faint);font-size:10.5px;line-height:1.1;letter-spacing:.02em}
.top-right{display:flex;align-items:center;gap:var(--s2);flex:none}
.chip{display:inline-flex;align-items:center;gap:7px;height:32px;padding:0 11px;border:1px solid var(--line);border-radius:999px;background:var(--surface);color:var(--dim);font-size:11px;line-height:1;white-space:nowrap}
.dot{display:block;width:7px;height:7px;border-radius:50%;background:var(--faint);flex:none;transition:background .3s,box-shadow .3s}
.dot.on{background:var(--ok);box-shadow:0 0 0 3px rgba(74,222,128,.15)}
.dot.warn{background:var(--warn);box-shadow:0 0 0 3px rgba(240,184,73,.15)}
.dot.bad{background:var(--bad)}
.iconbtn{display:grid;width:36px;height:36px;flex:none;place-items:center;border:1px solid var(--line);border-radius:var(--rs);background:var(--surface);color:var(--dim);font-size:15px;transition:transform .1s,background .15s,color .15s,border-color .15s}
.iconbtn:hover{color:var(--text);background:var(--raised);border-color:var(--edge)}
.iconbtn:active{transform:scale(.92)}
.iconbtn.spin{animation:spin .6s cubic-bezier(.4,0,.2,1)}
@keyframes spin{to{transform:rotate(360deg)}}

.view{display:grid;gap:var(--s3);animation:viewin .3s cubic-bezier(.2,.7,.3,1)}
@keyframes viewin{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}

/* ---------- Cartes ---------- */
.card{border:1px solid var(--line);border-radius:var(--r);background:var(--surface);overflow:hidden}
.card-h{display:flex;align-items:center;justify-content:space-between;gap:var(--s3);min-height:48px;padding:var(--s3) var(--s4);border-bottom:1px solid var(--line)}
.card-h h2{margin:0;font-size:13px;font-weight:650;letter-spacing:-.01em}
.card-h .sub{color:var(--faint);font-size:10px;text-transform:uppercase;letter-spacing:.09em;white-space:nowrap}
.card-h .tools{display:flex;align-items:center;gap:var(--s2);flex:none}
.card-b{padding:var(--s4)}
.card-b.flush{padding:0}
.msg{display:flex;align-items:center;gap:10px;margin:0;font-size:13.5px;line-height:1.4}

/* ---------- Grille de métriques ---------- */
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--line)}
.grid.one{grid-template-columns:1fr}
.cell{display:flex;flex-direction:column;gap:var(--s2);min-width:0;padding:var(--s3) var(--s4) var(--s4);background:var(--surface)}
.cell .k{display:block;color:var(--faint);font-size:9.5px;font-weight:600;text-transform:uppercase;letter-spacing:.1em;line-height:1.2}
.cell .val{display:block;margin-top:auto;font-size:18px;font-weight:650;letter-spacing:-.02em;line-height:1.1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/* La barre DOIT être en block : en inline la hauteur est ignorée (gros pavé blanc). */
.cell .bar{display:block;width:100%;height:3px;background:var(--line);border-radius:2px;overflow:hidden}
.cell .bar i{display:block;height:100%;width:0;background:var(--dim);border-radius:2px;transition:width .55s cubic-bezier(.2,.7,.3,1),background .3s}
.cell .bar i.warm{background:var(--warn)}
.cell .bar i.hot{background:var(--bad)}

/* ---------- Boutons ---------- */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:var(--s2);width:100%;min-height:46px;padding:0 var(--s4);
  border:1px solid var(--edge);border-radius:var(--ri);background:var(--surface);color:var(--text);
  font-size:13.5px;font-weight:550;line-height:1;white-space:nowrap;
  transition:transform .09s,background .16s,border-color .16s,color .16s}
.btn:hover{background:var(--raised)}
.btn:active{transform:scale(.975)}
.btn.pri{background:var(--text);color:var(--inverse);border-color:var(--text);font-weight:700}
.btn.pri:hover{background:#e6e6e3}
.btn.bad{color:var(--bad);border-color:#4a2a26}
.btn.bad:hover{background:var(--bad);color:var(--inverse);border-color:var(--bad)}
.btn.sm{width:auto;min-height:38px;padding:0 var(--s3);font-size:12.5px;border-radius:var(--rs)}
.btn.ghost{border-color:transparent;background:transparent;color:var(--faint)}
.btn.ghost:hover{color:var(--text);background:var(--raised)}
.row{display:grid;gap:var(--s2)}
.row.two{grid-template-columns:1fr 1fr}
.row.three{grid-template-columns:repeat(3,1fr)}
.row .btn.sm{width:100%}
.seg{display:grid;grid-auto-flow:column;grid-auto-columns:1fr;gap:var(--s1);padding:var(--s1);border:1px solid var(--line);border-radius:var(--ri);background:var(--bg)}
.seg button{min-height:40px;padding:0 var(--s2);border-radius:var(--rs);color:var(--dim);font-size:12.5px;font-weight:600;white-space:nowrap;transition:background .18s,color .18s}
.seg button:hover{color:var(--text)}
.seg button.active{background:var(--text);color:var(--inverse)}

/* ---------- Écran distant ---------- */
.screen-wrap{position:relative;background:#000;line-height:0;touch-action:none;user-select:none;overflow:hidden;aspect-ratio:16/9}
.screen-wrap img{display:block;width:100%;height:100%;object-fit:contain}
.screen-wrap .ph{position:absolute;inset:0;display:grid;place-items:center;color:var(--faint);font-size:12px;line-height:1.4}
.rcursor{position:absolute;top:0;left:0;width:16px;height:16px;margin:-8px 0 0 -8px;pointer-events:none;z-index:5;transition:transform .08s linear;will-change:transform}
.rcursor::before,.rcursor::after{content:"";position:absolute;inset:0;border-radius:50%}
.rcursor::before{border:2px solid rgba(0,0,0,.85);inset:-1px}
.rcursor::after{border:2px solid #fff}
.rcursor.hide{opacity:0}
.tap{position:absolute;width:34px;height:34px;margin:-17px 0 0 -17px;border:2px solid #fff;border-radius:50%;pointer-events:none;z-index:6;animation:tap .45s ease-out forwards}
.tap.right{border-color:var(--accent)}
@keyframes tap{from{transform:scale(.2);opacity:.9}to{transform:scale(1.4);opacity:0}}
.livebadge{position:absolute;top:var(--s2);left:var(--s2);z-index:6;display:flex;align-items:center;gap:6px;height:22px;padding:0 9px;border-radius:999px;background:rgba(0,0,0,.6);backdrop-filter:blur(6px);color:#fff;font-size:9.5px;font-weight:600;letter-spacing:.09em}
.livebadge i{display:block;width:6px;height:6px;border-radius:50%;background:var(--ok);animation:pulse 1.4s infinite}
@keyframes pulse{50%{opacity:.25}}
.fps{position:absolute;top:var(--s2);right:var(--s2);z-index:6;height:22px;padding:0 8px;display:flex;align-items:center;border-radius:999px;background:rgba(0,0,0,.55);backdrop-filter:blur(6px);color:#c9c9cf;font-size:9.5px}
.keys{display:grid;grid-template-columns:repeat(6,1fr);gap:var(--s2)}
.keys button{min-height:44px;border:1px solid var(--line);border-radius:var(--rs);background:var(--bg);color:var(--text);font-size:13px;transition:transform .09s,background .15s,border-color .15s}
.keys button:hover{border-color:var(--edge)}
.keys button:active{transform:scale(.92);background:var(--raised)}
.kbar{display:flex;gap:var(--s2)}
.kbar input{flex:1;min-width:0;min-height:46px;padding:0 var(--s3);border:1px solid var(--edge);border-radius:var(--ri);background:var(--bg);font-size:16px}
.kbar input::placeholder{color:var(--faint)}
.vol{display:flex;align-items:center;gap:var(--s3)}
.vol .lab{color:var(--faint);font-size:10px;font-weight:600;letter-spacing:.09em;flex:none}
.vol input[type=range]{flex:1;min-width:0;accent-color:var(--text);height:28px}
.vol .val{width:48px;text-align:right;font-size:13px;flex:none}

/* ---------- Fichiers ---------- */
.crumb{display:flex;align-items:center;gap:2px;flex-wrap:wrap;min-height:46px;padding:var(--s3) var(--s4);border-bottom:1px solid var(--line);font-size:12px;color:var(--faint);line-height:1.5}
.crumb b{color:var(--text);font-weight:600}
.crumb button{color:var(--dim);font-size:12px;padding:2px 3px;border-radius:5px}
.crumb button:hover{color:var(--text);background:var(--raised)}
.crumb .sep{color:var(--faint);opacity:.5}
.toolbar{display:flex;gap:var(--s2);flex-wrap:wrap;padding:var(--s3) var(--s4);border-bottom:1px solid var(--line)}
.list{display:grid}
.item{display:grid;grid-template-columns:22px minmax(0,1fr) auto;align-items:center;gap:var(--s3);width:100%;min-height:58px;padding:var(--s3) var(--s4);border-bottom:1px solid var(--line);text-align:left;transition:background .13s;animation:rowin .22s ease both}
@keyframes rowin{from{opacity:0;transform:translateY(3px)}to{opacity:1;transform:none}}
.item:last-child{border-bottom:0}
.item:hover{background:var(--raised)}
.item:active{background:var(--raised)}
.item .ic{font-size:15px;line-height:1;text-align:center}
.item .nm{min-width:0;display:flex;flex-direction:column;gap:2px}
.item .nm b{font-size:13.5px;font-weight:500;line-height:1.25;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.item .nm span{color:var(--faint);font-size:10.5px;line-height:1.2}
.item .go{color:var(--faint);font-size:14px;line-height:1}
.empty{margin:0;padding:var(--s6) var(--s4);text-align:center;color:var(--faint);font-size:12.5px}

/* ---------- Terminal ---------- */
.term{margin:0;padding:var(--s3);background:#08080a;border:1px solid var(--line);border-radius:var(--ri);
  max-height:46vh;min-height:132px;overflow:auto;font-size:12px;line-height:1.6;white-space:pre-wrap;word-break:break-word;color:#d2d2d6}
.term .cmd{color:var(--accent)}
.term .err{color:var(--bad)}
.term .ok{color:var(--faint)}
.term-in{display:flex;gap:var(--s2);margin-top:var(--s3)}
.term-in input{flex:1;min-width:0;min-height:46px;padding:0 var(--s3);border:1px solid var(--edge);border-radius:var(--ri);background:var(--bg);font-family:ui-monospace,Consolas,monospace;font-size:16px}

/* ---------- Système ---------- */
.proc{display:grid;grid-template-columns:minmax(0,1fr) auto auto;align-items:center;gap:var(--s3);min-height:56px;padding:var(--s3) var(--s4);border-bottom:1px solid var(--line)}
.proc:last-child{border-bottom:0}
.proc .nm{min-width:0;display:flex;flex-direction:column;gap:2px}
.proc .nm b{font-size:12.5px;font-weight:550;line-height:1.25;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.proc .nm span{color:var(--faint);font-size:10.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.proc .mem{color:var(--dim);font-size:12px;white-space:nowrap;font-variant-numeric:tabular-nums}
.kv{display:flex;align-items:center;justify-content:space-between;gap:var(--s3);min-height:48px;padding:var(--s3) 0;border-bottom:1px solid var(--line)}
.kv:first-child{padding-top:0}
.kv:last-child{border-bottom:0;padding-bottom:0}
.kv .lab{color:var(--dim);font-size:12px;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.kv .meter{display:block;flex:1;max-width:130px;height:4px;background:var(--line);border-radius:2px;overflow:hidden}
.kv .meter i{display:block;height:100%;background:var(--dim);border-radius:2px;transition:width .5s cubic-bezier(.2,.7,.3,1)}
.kv .meter i.hot{background:var(--bad)}
.kv b{font-size:13px;font-weight:600;white-space:nowrap;flex:none}
.apps{display:grid;grid-template-columns:repeat(4,1fr);gap:var(--s2)}
.apps button{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;min-height:72px;padding:var(--s2) 4px;
  border:1px solid var(--line);border-radius:var(--ri);background:var(--bg);font-size:10px;font-weight:550;line-height:1.2;text-align:center;
  transition:transform .09s,background .15s,border-color .15s}
.apps button:hover{border-color:var(--edge);background:var(--raised)}
.apps button:active{transform:scale(.94)}
.apps .ap-ic{font-size:20px;line-height:1}
.apps .ap-nm{max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

/* ---------- Navigation ---------- */
.nav{position:fixed;inset-inline:0;bottom:0;z-index:40;display:grid;grid-template-columns:repeat(5,1fr);
  height:calc(var(--nav) + env(safe-area-inset-bottom));padding-bottom:env(safe-area-inset-bottom);
  background:rgba(12,12,14,.86);backdrop-filter:blur(18px) saturate(1.3);border-top:1px solid var(--line)}
.nav button{position:relative;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;color:var(--faint);font-size:9.5px;font-weight:550;letter-spacing:.01em;transition:color .2s}
.nav button .ni{font-size:18px;line-height:1;transition:transform .22s cubic-bezier(.2,.8,.2,1)}
.nav button.active{color:var(--text)}
.nav button.active .ni{transform:translateY(-1px)}
.nav button:active .ni{transform:scale(.9)}

/* ---------- Portail d'accès ---------- */
.gate{display:grid;min-height:100dvh;place-items:center;padding:var(--s5)}
.gate .box{width:min(100%,380px);animation:viewin .38s ease}
.gate .logo{width:48px;height:48px;font-size:16px;border-radius:14px;margin-bottom:var(--s5)}
.gate h1{margin:0 0 6px;font-size:27px;font-weight:700;letter-spacing:-.03em}
.gate p{margin:0 0 var(--s5);color:var(--dim);font-size:13.5px;line-height:1.5}
.gate input{width:100%;min-height:52px;padding:0 var(--s4);margin-bottom:var(--s2);border:1px solid var(--edge);border-radius:var(--ri);background:var(--surface);font-size:16px}
.gate input::placeholder{color:var(--faint)}
.gate .btn{min-height:52px}
.gate .err{min-height:18px;margin:var(--s2) 2px 0;color:var(--bad);font-size:12px}

/* ---------- Superpositions ---------- */
.busy{position:fixed;inset:0 0 auto;z-index:60;height:2px;overflow:hidden;pointer-events:none}
.busy.on::after{content:"";position:absolute;inset-block:0;width:38%;background:linear-gradient(90deg,transparent,var(--accent),transparent);animation:load .9s infinite}
@keyframes load{from{left:-38%}to{left:100%}}
.toast{position:fixed;left:50%;bottom:calc(var(--nav) + var(--s4) + env(safe-area-inset-bottom));transform:translate(-50%,14px);z-index:70;
  max-width:calc(100% - 32px);padding:11px var(--s4);border:1px solid var(--edge);border-radius:999px;background:var(--raised);
  font-size:12.5px;line-height:1.3;box-shadow:0 10px 30px rgba(0,0,0,.55);opacity:0;pointer-events:none;
  transition:opacity .22s,transform .22s cubic-bezier(.2,.8,.2,1)}
.toast.show{opacity:1;transform:translate(-50%,0)}
.toast.bad{border-color:var(--bad)}
.toast.ok{border-color:var(--ok)}
.prog{position:fixed;left:50%;bottom:calc(var(--nav) + var(--s4) + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:70;
  width:min(calc(100% - 32px),340px);padding:var(--s3) var(--s4);border:1px solid var(--edge);border-radius:var(--r);background:var(--raised);box-shadow:0 10px 30px rgba(0,0,0,.55)}
.prog span{display:block;font-size:11.5px;color:var(--dim);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.prog .track{display:block;height:5px;margin-top:var(--s2);background:var(--line);border-radius:3px;overflow:hidden}
.prog .track i{display:block;height:100%;width:0;background:var(--accent);border-radius:3px;transition:width .2s}
dialog{width:min(100% - 32px,410px);padding:0;border:1px solid var(--edge);border-radius:var(--r);background:var(--surface);color:var(--text);animation:dlgin .24s cubic-bezier(.2,.8,.2,1)}
@keyframes dlgin{from{opacity:0;transform:translateY(8px) scale(.985)}to{opacity:1;transform:none}}
dialog::backdrop{background:rgba(0,0,0,.72);backdrop-filter:blur(4px)}
.dlg{padding:var(--s5)}
.dlg h3{margin:0 0 6px;font-size:17px;font-weight:650;letter-spacing:-.01em;word-break:break-word}
.dlg p{margin:0 0 var(--s5);color:var(--dim);font-size:13px;line-height:1.5;word-break:break-word}
.dlg input,.dlg textarea{width:100%;min-height:46px;padding:12px;margin-bottom:var(--s3);border:1px solid var(--edge);border-radius:var(--ri);background:var(--bg);font-size:16px}
.dlg textarea{min-height:150px;resize:vertical;font-family:ui-monospace,Consolas,monospace;font-size:13px;line-height:1.5}
.dlg img{display:block;width:100%;border-radius:var(--ri);margin-bottom:var(--s3)}
.dlg .row{margin-top:0}

/* ---------- Écrans étroits / larges ---------- */
@media(max-width:380px){
  .apps{grid-template-columns:repeat(3,1fr)}
  .keys{grid-template-columns:repeat(4,1fr)}
  .cell .val{font-size:16px}
}
@media(min-width:600px){
  .app{padding-inline:var(--s4)}
  .apps{grid-template-columns:repeat(6,1fr)}
}
@media(prefers-reduced-motion:reduce){*{animation-duration:.01ms!important;transition-duration:.01ms!important}}
"""

SCRIPT = r"""
(()=>{"use strict";
const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>[...r.querySelectorAll(s)];
const KEY="pcControlKey";
const gate=$("#gate"),app=$("#app"),field=$("#key"),gateErr=$("#gateErr"),busyEl=$("#busy"),toastEl=$("#toast");
let key=localStorage.getItem(KEY)||"";
let data=null,tab="home",stream=null,streamStop=null,busyN=0,toastT=0;
let scr={on:false,seq:-1,inflight:false,mon:-1,monitors:[],raf:0,frames:0,fpsT:0,clickMode:"left",scrollMode:false,last:0};
let filePath="",fileSort="name";
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const fmtDur=m=>{if(!Number.isFinite(m))return"—";const h=Math.floor(m/60),n=Math.round(m%60),d=Math.floor(h/24);return d?`${d}j ${h%24}h`:h?`${h}h${String(n).padStart(2,"0")}`:`${n}min`};
const human=b=>{if(b==null)return"";if(b<1024)return b+" o";if(b<1048576)return(b/1024).toFixed(0)+" Ko";if(b<1073741824)return(b/1048576).toFixed(1)+" Mo";return(b/1073741824).toFixed(2)+" Go"};
function vibe(ms=6){try{navigator.vibrate&&navigator.vibrate(ms)}catch{}}
function setBusy(v){busyN=Math.max(0,busyN+(v?1:-1));busyEl.classList.toggle("on",busyN>0)}
function toast(t,kind){toastEl.textContent=t;toastEl.className="toast show "+(kind||"");clearTimeout(toastT);toastT=setTimeout(()=>toastEl.className="toast",2400)}

async function api(path,method="GET",body){
  const o={method,cache:"no-store",headers:{Authorization:"Bearer "+key}};
  if(body){o.headers["Content-Type"]="application/json";o.body=JSON.stringify(body)}
  let r;try{r=await fetch(path,o)}catch{throw Error("Pas de réseau")}
  const d=await r.json().catch(()=>({}));
  if(r.status===401){const e=Error("Clé refusée");e.un=true;throw e}
  if(!r.ok){const e=Error(d.error||"Action impossible");e.status=r.status;throw e}
  return d;
}
async function act(action,args,quiet){
  if(!quiet)setBusy(true);
  try{return await api("/api/action","POST",{action,args:args||{}})}
  catch(e){if(e.un)return lock("Clé refusée");if(!quiet)toast(e.message,"bad");throw e}
  finally{if(!quiet)setBusy(false)}
}
function lock(reason){stopStream();stopScreen();localStorage.removeItem(KEY);key="";app.hidden=true;gate.hidden=false;field.value="";gateErr.textContent=reason||"";setTimeout(()=>field.focus(),0)}
function unlock(v){key=(v||"").trim();if(!key){gateErr.textContent="Saisis la clé.";return}localStorage.setItem(KEY,key);gate.hidden=true;app.hidden=false;start()}

/* Status stream */
function start(){refresh();connectStream();switchTab(tab)}
async function refresh(){try{apply(await api("/api/status"))}catch(e){if(e.un)lock(e.message)}}
function connectStream(){
  if(stream)return;const ctrl=new AbortController();streamStop=()=>ctrl.abort();
  fetch("/api/events",{cache:"no-store",headers:{Authorization:"Bearer "+key},signal:ctrl.signal}).then(async r=>{
    if(r.status===401)return lock("Clé refusée");if(!r.ok||!r.body)throw 0;stream=r;
    const rd=r.body.getReader(),dec=new TextDecoder();let buf="";
    for(;;){const p=await rd.read();if(p.done)break;buf+=dec.decode(p.value,{stream:true});let i;
      while((i=buf.indexOf("\n\n"))>=0){const f=buf.slice(0,i);buf=buf.slice(i+2);const l=f.split("\n").find(x=>x.startsWith("data: "));if(l){try{apply(JSON.parse(l.slice(6)))}catch{}}}}
  }).catch(()=>{}).finally(()=>{stream=null;if(key&&!document.hidden)setTimeout(connectStream,2000)});
}
function stopStream(){if(streamStop)streamStop();stream=null}
function apply(d){data=d;const on=!!d.online,ready=!!d.control_ready;
  $("#device").textContent=d.pc?.computer||"GTOL";
  $("#hdot").className="dot "+(ready?"on":on?"warn":"off");
  $("#hstate").textContent=ready?"En ligne":on?"Pont muet":"Éteinte";
  if(tab==="home")renderHome(d);
}

/* Home */
function metric(id,val,pct,hot){const e=$("#m_"+id);if(!e)return;e.querySelector(".val").textContent=val;const b=e.querySelector("i");if(b){b.style.width=(Number.isFinite(pct)?clamp(pct,0,100):0)+"%";b.className=hot==="hot"?"hot":hot==="warm"?"warm":""}}
function renderHome(d){const pc=d.pc||{},on=!!d.online,ready=!!d.control_ready;
  $("#homeMsg").textContent=d.message||(on?"Tour en ligne":"Tour éteinte");
  $("#homeMsg").previousElementSibling.className="dot "+(ready?"on":on?"warn":"off");
  metric("cpu",Number.isFinite(pc.cpu_load_percent)?pc.cpu_load_percent+"%":"—",pc.cpu_load_percent,pc.cpu_load_percent>=90?"hot":pc.cpu_load_percent>=70?"warm":"");
  metric("gpu",Number.isFinite(pc.gpu_load_percent)?pc.gpu_load_percent+"%":"—",pc.gpu_load_percent);
  metric("temp",Number.isFinite(pc.gpu_temperature_c)?pc.gpu_temperature_c+"°":"—",pc.gpu_temperature_c,pc.gpu_temperature_c>=82?"hot":pc.gpu_temperature_c>=72?"warm":"");
  metric("ram",Number.isFinite(pc.memory_free_gb)?pc.memory_free_gb+" Go":"—",pc.memory_used_percent,pc.memory_used_percent>=90?"warm":"");
  metric("disk",Number.isFinite(pc.disk_free_gb)?pc.disk_free_gb+" Go":"—",pc.disk_used_percent,pc.disk_used_percent>=92?"hot":"");
  metric("up",pc.uptime_minutes!=null?fmtDur(pc.uptime_minutes):"—",0);
  $("#wakeBtn").hidden=on;$("#lockBtn").hidden=!on;
  $("#modeNormal").classList.toggle("active",pc.mode==="normal");
  $("#modeNight").classList.toggle("active",pc.mode==="night");
  $$("[data-need-on]").forEach(b=>b.disabled=!on);
}

/* ===== Screen streaming ===== */
function screenWidth(){const w=$("#screenWrap").clientWidth||720;return clamp(Math.round(w*Math.min(2,window.devicePixelRatio||1)),640,1920)}
function startScreen(){if(scr.on)return;scr.on=true;scr.seq=-1;scr.frames=0;scr.fpsT=performance.now();$("#liveBadge").hidden=false;
  act("StreamStart",{monitor:scr.mon,width:screenWidth(),fps:15},true).catch(()=>{});loopScreen();}
function stopScreen(){scr.on=false;cancelAnimationFrame(scr.raf);$("#liveBadge")&&($("#liveBadge").hidden=true);if(data?.online)act("StreamStop",null,true).catch(()=>{})}
async function loopScreen(){
  if(!scr.on||tab!=="screen"){return}
  if(!scr.inflight){scr.inflight=true;
    try{
      const r=await api(`/api/screen?since=${scr.seq}&width=${screenWidth()}&monitor=${scr.mon}&fps=15`);
      if(r.ready===false){$("#screenPh").textContent="Démarrage du flux…"}
      else{
        if(r.image){const img=$("#screenImg");img.src="data:image/jpeg;base64,"+r.image;img.hidden=false;$("#screenPh").hidden=true;scr.seq=r.img_seq;}
        else if(r.img_seq!=null)scr.seq=r.img_seq;
        if(r.cursor)placeCursor(r.cursor,r.w,r.h);
        if(Array.isArray(r.monitors)&&r.monitors.length!==scr.monitors.length){scr.monitors=r.monitors;renderMonitors()}
        scr.frames++;const now=performance.now();if(now-scr.fpsT>=1000){$("#fps").textContent=scr.frames+" fps";scr.frames=0;scr.fpsT=now}
      }
    }catch(e){if(e.un){scr.inflight=false;return lock(e.message)}if(e.status===409){$("#screenPh").textContent="Tour éteinte";$("#screenPh").hidden=false;$("#screenImg").hidden=true}}
    finally{scr.inflight=false}
  }
  scr.raf=requestAnimationFrame(loopScreen);
}
function placeCursor(c,w,h){const cur=$("#rcursor"),img=$("#screenImg");if(!w||!h||img.hidden){cur.classList.add("hide");return}
  const rect=img.getBoundingClientRect();const x=c.x/w*rect.width,y=c.y/h*rect.height;
  cur.classList.toggle("hide",!c.on);cur.style.transform=`translate(${x}px,${y}px)`;}
function renderMonitors(){const box=$("#monitorSel");box.innerHTML="";if(scr.monitors.length<=1){box.hidden=true;return}box.hidden=false;
  const mk=(l,i)=>{const b=document.createElement("button");b.textContent=l;b.className=scr.mon===i?"active":"";b.onclick=()=>{scr.mon=i;scr.seq=-1;renderMonitors()};return b};
  box.appendChild(mk("Tous",-1));scr.monitors.forEach((m,i)=>box.appendChild(mk("É"+(i+1)+(m.primary?"·":""),i)));}
function ripple(x,y,right){const wrap=$("#screenWrap"),d=document.createElement("div");d.className="tap"+(right?" right":"");d.style.left=x+"px";d.style.top=y+"px";wrap.appendChild(d);setTimeout(()=>d.remove(),450)}
function normPt(ev){const img=$("#screenImg"),rect=img.getBoundingClientRect();return{nx:clamp((ev.clientX-rect.left)/rect.width,0,1),ny:clamp((ev.clientY-rect.top)/rect.height,0,1),lx:ev.clientX-rect.left,ly:ev.clientY-rect.top}}
function bindScreen(){
  const wrap=$("#screenWrap");let down=null,longT=0,moved=false,didLong=false;
  wrap.addEventListener("pointerdown",e=>{if($("#screenImg").hidden)return;down=normPt(e);moved=false;didLong=false;try{wrap.setPointerCapture(e.pointerId)}catch{}
    longT=setTimeout(()=>{didLong=true;vibe(12);ripple(down.lx,down.ly,true);act("Click",{monitor:scr.mon,nx:down.nx,ny:down.ny,button:"right"},true).catch(()=>{})},480)});
  wrap.addEventListener("pointermove",e=>{if(!down)return;const p=normPt(e);if(Math.hypot(p.lx-down.lx,p.ly-down.ly)>10)moved=true;});
  wrap.addEventListener("pointerup",e=>{if(!down){return}clearTimeout(longT);const p=normPt(e);
    if(didLong){down=null;return}
    if(moved){
      if(scr.scrollMode){const dy=Math.round((down.ny-p.ny)*2400);act("Scroll",{amount:dy},true).catch(()=>{});}
      else{vibe();act("Drag",{monitor:scr.mon,nx:down.nx,ny:down.ny,nx2:p.nx,ny2:p.ny,button:"left"},true).catch(()=>{});}
    }else{
      const dbl=scr.clickMode==="double";vibe();ripple(down.lx,down.ly,scr.clickMode==="right");
      act("Click",{monitor:scr.mon,nx:down.nx,ny:down.ny,button:scr.clickMode==="right"?"right":"left",double:dbl},true).catch(()=>{});
    }
    down=null;});
}

/* ===== Files (with chunked transfers) ===== */
function b64ToBytes(b64){const bin=atob(b64),a=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i);return a}
function bytesToB64(bytes){let bin="";const CH=0x8000;for(let i=0;i<bytes.length;i+=CH)bin+=String.fromCharCode.apply(null,bytes.subarray(i,i+CH));return btoa(bin)}
async function loadDir(path){filePath=path;setBusy(true);
  try{renderDir(await act("FsList",{path},true))}catch(e){if(e.un)return lock(e.message);$("#fileList").innerHTML='<p class="empty">'+esc(e.message)+"</p>"}finally{setBusy(false)}}
function sortEntries(list){const dirs=list.filter(e=>e.dir),files=list.filter(e=>!e.dir);
  const by=fileSort==="size"?(a,b)=>(b.size||0)-(a.size||0):fileSort==="date"?(a,b)=>(b.modified||0)-(a.modified||0):(a,b)=>a.name.localeCompare(b.name);
  files.sort(by);dirs.sort((a,b)=>a.name.localeCompare(b.name));return[...dirs,...files]}
function renderDir(r){const list=$("#fileList");list.innerHTML="";
  $("#crumb").innerHTML=r.is_root?"<b>Disques</b>":crumbHtml(r.path);
  $("#fileToolbar").hidden=!!r.is_root;
  const entries=sortEntries(r.entries||[]);
  if(!entries.length){list.innerHTML='<p class="empty">Dossier vide</p>';return}
  for(const e of entries){const b=document.createElement("button");b.className="item";
    b.innerHTML=`<span class="ic">${e.dir?"📁":icon(e.name)}</span><span class="nm"><b>${esc(e.name)}</b><span>${e.dir?"":human(e.size)}</span></span><span class="go">${e.dir?"›":"⋯"}</span>`;
    b.onclick=()=>e.dir?loadDir(e.path):fileMenu(e);list.appendChild(b);}
}
function crumbHtml(p){const parts=p.replace(/\\+$/,"").split("\\");let acc="";return parts.map((s,i)=>{acc+=(i?"\\":"")+s;const cur=acc+(i===0?"\\":"");return i===parts.length-1?`<b>${esc(s||p)}</b>`:`<button data-p="${esc(cur)}">${esc(s)}</button>`}).join('<span class="sep">\\</span>')}
const ICONS={txt:"📄",log:"📄",md:"📝",json:"🔧",js:"📜",ts:"📜",py:"🐍",html:"🌐",css:"🎨",jpg:"🖼️",jpeg:"🖼️",png:"🖼️",gif:"🖼️",webp:"🖼️",mp4:"🎬",mkv:"🎬",mov:"🎬",mp3:"🎵",wav:"🎵",zip:"🗜️",rar:"🗜️",exe:"⚙️",pdf:"📕",doc:"📘",docx:"📘",xls:"📗",xlsx:"📗"};
function icon(n){const x=(n.split(".").pop()||"").toLowerCase();return ICONS[x]||"📄"}
function isImg(n){return/\.(jpe?g|png|gif|webp|bmp)$/i.test(n)}
async function fileMenu(e){const opts=[["Ouvrir sur le PC","open"]];
  if(isImg(e.name))opts.unshift(["Aperçu image","img"]);else opts.unshift(["Aperçu texte","view"]);
  opts.push(["Télécharger","dl"],["Renommer","ren"],["Supprimer","del"]);
  const c=await pick(e.name,opts);
  if(c==="view")try{const r=await act("FsRead",{path:e.path});textDlg(e.name,r.text)}catch(err){toast(err.message,"bad")}
  else if(c==="img")imgDlg(e);
  else if(c==="dl")downloadFile(e);
  else if(c==="open")act("OpenPath",{path:e.path}).then(r=>toast(r.message||"Ouvert","ok")).catch(()=>{});
  else if(c==="ren"){const nn=await prompt2("Renommer",e.name);if(nn)await act("FsRename",{path:e.path,name:nn}).then(()=>{toast("Renommé","ok");loadDir(filePath)}).catch(err=>toast(err.message,"bad"))}
  else if(c==="del"&&await confirm2("Supprimer ?",e.name))await act("FsDelete",{path:e.path,recurse:e.dir}).then(()=>{toast("Supprimé","ok");loadDir(filePath)}).catch(err=>toast(err.message,"bad"))}
async function imgDlg(e){try{const r=await act("FsDownload",{path:e.path});const url="data:image/*;base64,"+r.content_base64;$("#dlgBody").innerHTML=`<h3>${esc(e.name)}</h3><img src="${url}"><button class="btn" id="dc">Fermer</button>`;$("#dlg").showModal();$("#dc").onclick=()=>$("#dlg").close()}catch(err){toast(err.message,"bad")}}
function saveBlob(blob,name){const url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),2000)}
async function downloadFile(e){
  let size=e.size;try{if(size==null){size=(await act("FsStat",{path:e.path},true)).size}}catch{}
  if(size!=null&&size>4*1024*1024){
    const CH=3*1024*1024;let off=0;const parts=[];showProg("Téléchargement");
    try{for(;;){const r=await act("FsDownloadChunk",{path:e.path,offset:off,length:CH},true);parts.push(b64ToBytes(r.content_base64));off=r.offset+ (r.read||0);setProg(off/r.total);if(r.eof||!r.read)break}saveBlob(new Blob(parts),e.name);toast("Téléchargé","ok")}
    catch(err){toast(err.message,"bad")}finally{hideProg()}
  }else{try{const r=await act("FsDownload",{path:e.path});saveBlob(new Blob([b64ToBytes(r.content_base64)]),r.name||e.name);toast("Téléchargé","ok")}catch(err){toast(err.message,"bad")}}
}
async function uploadFiles(files){for(const f of files)await uploadOne(f)}
async function uploadOne(file){const buf=new Uint8Array(await file.arrayBuffer());const total=buf.length;const target=filePath.replace(/\\+$/,"")+"\\"+file.name;
  const CH=700*1024;let off=0;showProg("Envoi "+file.name);
  try{if(total===0){await act("FsWriteChunk",{path:target,offset:0,content_base64:""},true)}
    while(off<total){const slice=buf.subarray(off,off+CH);await act("FsWriteChunk",{path:target,offset:off,content_base64:bytesToB64(slice)},true);off+=slice.length;setProg(off/total)}
    toast("Envoyé","ok");loadDir(filePath)}catch(err){toast(err.message,"bad")}finally{hideProg()}}

/* ===== System ===== */
let procSort="mem";
async function loadSystem(){try{const [p,dr,info]=await Promise.all([act("Processes",null,true),act("Drives",null,true),act("SessionInfo",null,true).catch(()=>null)]);
  renderProc(p.processes||[]);renderDrives(dr.drives||[]);renderApps(info?.apps||[]);if(info)renderVol(info)}catch(e){if(e.un)lock(e.message)}}
function renderVol(info){const el=$("#sysVol");if(!el)return;el.querySelector(".val").textContent=(info.muted?"🔇 ":"")+ (info.volume??"—")+"%"}
function renderProc(list){const box=$("#procList");box.innerHTML="";
  list.sort(procSort==="mem"?(a,b)=>b.memory_mb-a.memory_mb:(a,b)=>a.name.localeCompare(b.name));
  if(!list.length){box.innerHTML='<p class="empty">—</p>';return}
  list.slice(0,24).forEach(p=>{const row=document.createElement("div");row.className="proc";
    row.innerHTML=`<span class="nm"><b>${esc(p.name)}</b><span>${esc(p.window||"pid "+p.pid)}</span></span><span class="mem">${p.memory_mb} Mo</span>`;
    const k=document.createElement("button");k.className="btn bad sm";k.textContent="Kill";
    k.onclick=async()=>{if(await confirm2("Arrêter ?",p.name))await act("KillProcess",{pid:p.pid}).then(r=>{toast(r.message||"Arrêté","ok");loadSystem()}).catch(err=>toast(err.message,"bad"))};
    row.appendChild(k);box.appendChild(row)})}
function renderDrives(list){const box=$("#driveList");box.innerHTML="";list.forEach(d=>{const row=document.createElement("div");row.className="kv";
  const pct=d.used_percent||0;
  row.innerHTML=`<span class="lab">${esc(d.name)} ${esc(d.label||d.type)}</span><span class="meter"><i class="${pct>=92?"hot":""}" style="width:${pct}%"></i></span><b>${d.free_gb} Go</b>`;box.appendChild(row)})}
const APP_IC={chrome:"🌐",edge:"🌐",explorer:"🗂️",notepad:"📝",terminal:"⌨️",taskmgr:"📊",parsec:"🖥️",spotify:"🎵",steam:"🎮",discord:"💬",vscode:"🧩",fancontrol:"🌀"};
function renderApps(list){const box=$("#appList");box.innerHTML="";if(!list.length){box.innerHTML='<p class="empty">Agent requis</p>';return}
  list.forEach(a=>{const b=document.createElement("button");b.innerHTML=`<span class="ap-ic">${APP_IC[a.id]||"▶"}</span><span class="ap-nm">${esc(a.name)}</span>`;
    b.onclick=()=>{vibe();act("Launch",{app:a.id}).then(r=>toast(r.message||"Lancé","ok")).catch(()=>{})};box.appendChild(b)})}

/* ===== Terminal ===== */
let termShell="powershell",termHist=[],termIdx=-1;
function termWrite(html){const t=$("#termOut");t.insertAdjacentHTML("beforeend",html);t.scrollTop=t.scrollHeight}
async function runCmd(cmd){if(!cmd.trim())return;termHist.unshift(cmd);termIdx=-1;
  termWrite(`<div class="cmd">${termShell==="cmd"?">":"PS>"} ${esc(cmd)}</div>`);setBusy(true);
  try{const r=await act("Exec",{command:cmd,shell:termShell},true);
    if(r.stdout)termWrite(`<div>${esc(r.stdout)}</div>`);if(r.stderr)termWrite(`<div class="err">${esc(r.stderr)}</div>`);
    termWrite(`<div class="ok">— code ${r.exit_code}</div>`)}catch(e){termWrite(`<div class="err">${esc(e.message)}</div>`)}finally{setBusy(false)}}

/* ===== Nav ===== */
function switchTab(name){if(name!=="screen")stopScreen();tab=name;
  $$(".view").forEach(v=>v.hidden=v.id!=="view-"+name);
  $$(".nav button").forEach(b=>b.classList.toggle("active",b.dataset.tab===name));
  if(name==="home")renderHome(data||{});
  if(name==="screen"){$("#screenPh").hidden=false;$("#screenPh").textContent="Connexion…";startScreen()}
  if(name==="files")loadDir(filePath||"");
  if(name==="system")loadSystem();
  if(name==="terminal")setTimeout(()=>$("#termIn").focus(),80);
  window.scrollTo(0,0)}

/* ===== Dialogs ===== */
const dlg=$("#dlg");let dres=null;
function closeDlg(v){if(dres){const r=dres;dres=null;r(v)}dlg.close()}
function confirm2(t,x){return new Promise(r=>{dres=r;$("#dlgBody").innerHTML=`<h3>${esc(t)}</h3><p>${esc(x)}</p><div class="row two"><button class="btn" id="n">Annuler</button><button class="btn bad" id="y">Confirmer</button></div>`;dlg.showModal();$("#n").onclick=()=>closeDlg(false);$("#y").onclick=()=>closeDlg(true)})}
function pick(t,opts){return new Promise(r=>{dres=r;$("#dlgBody").innerHTML=`<h3>${esc(t)}</h3><div class="row">${opts.map(([l,v])=>`<button class="btn" data-v="${v}">${esc(l)}</button>`).join("")}<button class="btn" data-v="">Fermer</button></div>`;dlg.showModal();$$("#dlgBody [data-v]").forEach(b=>b.onclick=()=>closeDlg(b.dataset.v||null))})}
function prompt2(t,val){return new Promise(r=>{dres=r;$("#dlgBody").innerHTML=`<h3>${esc(t)}</h3><input id="pi" value="${esc(val||"")}" autocomplete="off"><div class="row two"><button class="btn" id="n">Annuler</button><button class="btn pri" id="y">OK</button></div>`;dlg.showModal();setTimeout(()=>$("#pi").select(),50);$("#n").onclick=()=>closeDlg(null);$("#y").onclick=()=>closeDlg($("#pi").value.trim()||null)})}
function textDlg(t,x){dres=null;$("#dlgBody").innerHTML=`<h3>${esc(t)}</h3><textarea readonly>${esc(x)}</textarea><div class="row two"><button class="btn" id="cp">Copier</button><button class="btn" id="cl">Fermer</button></div>`;dlg.showModal();$("#cl").onclick=()=>dlg.close();$("#cp").onclick=()=>{navigator.clipboard?.writeText(x);toast("Copié","ok")}}
dlg.addEventListener("cancel",()=>{if(dres)closeDlg(null)});
const progEl=$("#prog");function showProg(t){progEl.querySelector("span").textContent=t;progEl.querySelector("i").style.width="0";progEl.hidden=false}
function setProg(f){progEl.querySelector("i").style.width=clamp(f*100,0,100)+"%"}
function hideProg(){progEl.hidden=true}

/* ===== Bindings ===== */
$("#unlock").addEventListener("submit",e=>{e.preventDefault();unlock(field.value)});
$("#refreshBtn").addEventListener("click",e=>{vibe();e.currentTarget.classList.remove("spin");void e.currentTarget.offsetWidth;e.currentTarget.classList.add("spin");refresh();if(tab==="system")loadSystem();if(tab==="files")loadDir(filePath)});
$$(".nav button").forEach(b=>b.addEventListener("click",()=>{vibe();switchTab(b.dataset.tab)}));
$("#crumb").addEventListener("click",e=>{const b=e.target.closest("[data-p]");if(b)loadDir(b.dataset.p)});

// Home actions
async function legacy(action,cfx,label){vibe();if(cfx&&!(await confirm2(label,cfx)))return;setBusy(true);try{const r=await api("/api/control","POST",{action});toast(r.message||"OK","ok");setTimeout(refresh,600)}catch(e){if(e.un)lock(e.message);else toast(e.message,"bad")}finally{setBusy(false)}}
$("#wakeBtn").addEventListener("click",async()=>{vibe();try{const r=await api("/api/wake","POST");toast(r.message||"Signal envoyé","ok");setTimeout(refresh,1500)}catch(e){if(e.un)lock(e.message);else toast(e.message,"bad")}});
$("#lockBtn").addEventListener("click",()=>{vibe();act("Lock").then(r=>toast(r.message||"Verrouillé","ok")).catch(()=>{})});
$("#shareParsec").addEventListener("click",()=>legacy("share-parsec"));
$("#modeNormal").addEventListener("click",()=>legacy("normal"));
$("#modeNight").addEventListener("click",()=>legacy("night"));
$("#repairFans").addEventListener("click",()=>legacy("repair-fans"));
$("#launchCodex").addEventListener("click",()=>legacy("launch-codex"));
$("#rebootBtn").addEventListener("click",()=>legacy("reboot","Windows redémarre, Parsec sera coupé un instant.","Redémarrer"));
$("#hibernateBtn").addEventListener("click",()=>legacy("hibernate","Windows s'éteint. Le réveil Wake-on-LAN reste possible.","Éteindre"));
$("#displaysOff").addEventListener("click",()=>{vibe();act("DisplaysOff").then(r=>toast(r.message||"OK","ok")).catch(()=>{})});
$("#displaysOn").addEventListener("click",()=>{vibe();act("DisplaysOn").then(r=>toast(r.message||"OK","ok")).catch(()=>{})});

// Screen
bindScreen();
$$("[data-click]").forEach(b=>b.addEventListener("click",()=>{vibe();scr.clickMode=b.dataset.click;$$("[data-click]").forEach(x=>x.classList.toggle("active",x===b))}));
$("#scrollToggle").addEventListener("click",()=>{scr.scrollMode=!scr.scrollMode;$("#scrollToggle").classList.toggle("active",scr.scrollMode);$("#scrollToggle").textContent=scr.scrollMode?"Molette ●":"Molette ○"});
$("#fsBtn").addEventListener("click",()=>{const w=$("#screenWrap");if(w.requestFullscreen)w.requestFullscreen().catch(()=>{})});
$("#keyText").addEventListener("keydown",e=>{
  const special={Enter:"enter",Backspace:"backspace",Tab:"tab",Escape:"escape",ArrowUp:"up",ArrowDown:"down",ArrowLeft:"left",ArrowRight:"right",Delete:"delete"};
  if(special[e.key]){e.preventDefault();const mods=[];if(e.ctrlKey)mods.push("ctrl");if(e.altKey)mods.push("alt");if(e.shiftKey)mods.push("shift");act("SendKey",{key:special[e.key],modifiers:mods},true).catch(()=>{})}
});
$("#keyText").addEventListener("input",e=>{const v=e.target.value;if(v){act("TypeText",{text:v},true).catch(()=>{});e.target.value=""}});
$$("[data-key]").forEach(b=>b.addEventListener("click",()=>{vibe();act("SendKey",{key:b.dataset.key,modifiers:b.dataset.mods?b.dataset.mods.split(","):[]},true).catch(()=>{})}));
$$("[data-scroll]").forEach(b=>b.addEventListener("click",()=>{vibe();act("Scroll",{amount:+b.dataset.scroll},true).catch(()=>{})}));
$$("[data-media]").forEach(b=>b.addEventListener("click",()=>{vibe();act("Media",{command:b.dataset.media},true).then(r=>toast(r.message||"OK")).catch(()=>{})}));
$("#pasteClip").addEventListener("click",async()=>{try{const t=await navigator.clipboard.readText();if(t){await act("SetClipboard",{text:t});await act("SendKey",{key:"v",modifiers:["ctrl"]},true);toast("Collé sur le PC","ok")}}catch{toast("Presse-papiers refusé","bad")}});
const vr=$("#volRange");let vt=0;vr.addEventListener("input",()=>{$("#volVal").textContent=vr.value+"%";clearTimeout(vt);vt=setTimeout(()=>act("Volume",{level:+vr.value},true).catch(()=>{}),90)});

// Files
$("#fileUp").addEventListener("click",()=>loadDir(parentPath(filePath)));
$("#fileRefresh").addEventListener("click",()=>loadDir(filePath));
$("#newFolder").addEventListener("click",async()=>{const n=await prompt2("Nouveau dossier","");if(n)await act("FsMkdir",{path:filePath.replace(/\\+$/,"")+"\\"+n}).then(()=>{toast("Créé","ok");loadDir(filePath)}).catch(e=>toast(e.message,"bad"))});
$("#uploadInput").addEventListener("change",e=>{if(e.target.files.length)uploadFiles([...e.target.files]);e.target.value=""});
$("#sortBtn").addEventListener("click",()=>{fileSort=fileSort==="name"?"size":fileSort==="size"?"date":"name";$("#sortBtn").textContent="Tri: "+({name:"nom",size:"taille",date:"date"}[fileSort]);loadDir(filePath)});
function parentPath(p){const q=p.replace(/\\+$/,"");const i=q.lastIndexOf("\\");return i<=1?"":q.slice(0,i>2?i:3)}

// System
$("#sysRefresh").addEventListener("click",()=>{vibe();loadSystem()});
$("#procSort").addEventListener("click",()=>{procSort=procSort==="mem"?"name":"mem";$("#procSort").textContent="Tri: "+(procSort==="mem"?"mémoire":"nom");loadSystem()});

// Terminal
$$("[data-shell]").forEach(b=>b.addEventListener("click",()=>{termShell=b.dataset.shell;$$("[data-shell]").forEach(x=>x.classList.toggle("active",x===b))}));
$("#termForm").addEventListener("submit",e=>{e.preventDefault();const v=$("#termIn").value;$("#termIn").value="";runCmd(v)});
$("#termIn").addEventListener("keydown",e=>{if(e.key==="ArrowUp"){e.preventDefault();if(termIdx<termHist.length-1){termIdx++;$("#termIn").value=termHist[termIdx]}}else if(e.key==="ArrowDown"){e.preventDefault();if(termIdx>0){termIdx--;$("#termIn").value=termHist[termIdx]}else{termIdx=-1;$("#termIn").value=""}}});
$("#termClear").addEventListener("click",()=>$("#termOut").innerHTML="");
$("#forget").addEventListener("click",()=>{localStorage.removeItem(KEY);location.reload()});

document.addEventListener("visibilitychange",()=>{if(document.hidden){stopStream();stopScreen()}else if(key){connectStream();refresh();if(tab==="screen")startScreen()}});
addEventListener("resize",()=>{if(tab==="screen"&&data)placeCursor({x:0,y:0,on:false},1,1)});
const hk=new URLSearchParams(location.hash.slice(1)).get("k");if(hk?.trim()){key=hk.trim();localStorage.setItem(KEY,key);history.replaceState(null,"",location.pathname)}
navigator.storage?.persist?.().catch(()=>{});navigator.serviceWorker?.register("/sw.js",{updateViaCache:"none"}).catch(()=>{});
if(key){gate.hidden=true;app.hidden=false;start()}else field.focus();
})();
"""

BODY = r"""
<div class="busy" id="busy"></div>
<div class="toast" id="toast"></div>
<div class="prog" id="prog" hidden><span>…</span><div class="track"><i></i></div></div>

<main class="gate" id="gate">
  <div class="box">
    <div class="logo">GT</div>
    <h1>PC Control</h1>
    <p>Pilotage complet et privé de la tour GTOL.</p>
    <form id="unlock" novalidate>
      <input id="key" type="password" autocomplete="current-password" spellcheck="false" autocapitalize="off" enterkeyhint="go" placeholder="Clé d'accès">
      <button class="btn pri" type="submit" style="min-height:52px">Entrer</button>
      <p class="err" id="gateErr" role="alert"></p>
    </form>
  </div>
</main>

<main class="app" id="app" hidden>
  <header class="top">
    <div class="brand"><span class="logo">GT</span><span class="brand-txt"><b id="device">GTOL</b><small>PC Control</small></span></div>
    <div class="top-right"><span class="chip"><i class="dot" id="hdot"></i><span id="hstate">…</span></span><button class="iconbtn" id="refreshBtn" aria-label="Actualiser">↻</button></div>
  </header>

  <section class="view" id="view-home">
    <div class="card"><div class="card-b"><p class="msg"><span class="dot"></span><span id="homeMsg">Lecture…</span></p></div></div>
    <div class="card"><div class="card-b flush"><div class="grid">
      <div class="cell" id="m_cpu"><span class="k">CPU</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_gpu"><span class="k">GPU</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_temp"><span class="k">Temp GPU</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_ram"><span class="k">RAM libre</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_disk"><span class="k">Disque C</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_up"><span class="k">Uptime</span><span class="val">—</span><span class="bar"><i></i></span></div>
    </div></div></div>
    <div class="card"><div class="card-h"><h2>Contrôle rapide</h2></div><div class="card-b"><div class="row">
      <button class="btn pri" id="wakeBtn">Allumer la tour</button>
      <button class="btn" id="lockBtn" data-need-on hidden>Verrouiller</button>
      <button class="btn" id="shareParsec" data-need-on>Partager Parsec</button>
      <div class="seg"><button id="modeNormal" data-need-on>Normal</button><button id="modeNight" data-need-on>Nuit</button></div>
      <div class="row two"><button class="btn sm" id="displaysOff" data-need-on>Écrans off</button><button class="btn sm" id="displaysOn" data-need-on>Écrans on</button></div>
      <div class="row two"><button class="btn sm" id="repairFans" data-need-on>Ventilateurs</button><button class="btn sm" id="launchCodex" data-need-on>Lancer Codex</button></div>
    </div></div></div>
    <div class="card"><div class="card-h"><h2>Alimentation</h2><span class="sub">Confirmation</span></div><div class="card-b"><div class="row two">
      <button class="btn" id="rebootBtn" data-need-on>Redémarrer</button><button class="btn bad" id="hibernateBtn" data-need-on>Éteindre</button>
    </div></div></div>
    <div class="card"><div class="card-b"><button class="btn sm ghost" id="forget" style="width:100%">Oublier la clé</button></div></div>
  </section>

  <section class="view" id="view-screen" hidden>
    <div class="card"><div class="card-b flush"><div class="screen-wrap" id="screenWrap">
      <img id="screenImg" hidden alt="Écran">
      <div class="rcursor hide" id="rcursor"></div>
      <div class="livebadge" id="liveBadge" hidden><i></i>LIVE</div>
      <div class="fps" id="fps">— fps</div>
      <div class="ph" id="screenPh">Connexion…</div>
    </div></div></div>
    <div class="seg" style="grid-template-columns:1fr 1fr 1fr"><button data-click="left" class="active">Clic</button><button data-click="right">Droit</button><button data-click="double">Double</button></div>
    <div class="row three"><button class="btn sm" id="scrollToggle">Molette ○</button><button class="btn sm" id="pasteClip">Coller</button><button class="btn sm" id="fsBtn">Plein écran</button></div>
    <span id="monitorSel" class="seg" hidden></span>
    <div class="card"><div class="card-h"><h2>Clavier</h2></div><div class="card-b">
      <div class="kbar"><input id="keyText" placeholder="Tape ici (envoi live)…" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="send"></div>
      <div class="keys" style="margin-top:10px">
        <button data-key="enter">⏎</button><button data-key="backspace">⌫</button><button data-key="tab">⇥</button><button data-key="escape">esc</button><button data-key="up">↑</button><button data-key="down">↓</button>
        <button data-key="left">←</button><button data-key="right">→</button><button data-key="c" data-mods="ctrl">^C</button><button data-key="v" data-mods="ctrl">^V</button><button data-key="win">⊞</button><button data-key="delete">del</button>
      </div>
    </div></div>
    <div class="card"><div class="card-h"><h2>Défilement & son</h2></div><div class="card-b">
      <div class="row two" style="margin-bottom:12px"><button class="btn sm" data-scroll="700">▲ Haut</button><button class="btn sm" data-scroll="-700">▼ Bas</button></div>
      <div class="vol"><span class="lab">VOL</span><input type="range" id="volRange" min="0" max="100" value="50" aria-label="Volume"><span class="val" id="volVal">—</span></div>
      <div class="row three" style="margin-top:12px"><button class="btn sm" data-media="prev">⏮</button><button class="btn sm" data-media="playpause">⏯</button><button class="btn sm" data-media="next">⏭</button></div>
    </div></div>
  </section>

  <section class="view" id="view-files" hidden>
    <div class="card"><div class="crumb" id="crumb"><b>Disques</b></div>
      <div class="toolbar" id="fileToolbar" hidden>
        <button class="btn sm" id="fileUp" aria-label="Dossier parent">↑</button>
        <button class="btn sm" id="fileRefresh" aria-label="Actualiser">↻</button>
        <button class="btn sm" id="newFolder">+ Dossier</button>
        <label class="btn sm" style="cursor:pointer">↥ Envoyer<input type="file" id="uploadInput" multiple hidden></label>
        <button class="btn sm" id="sortBtn">Tri: nom</button>
      </div>
      <div class="list" id="fileList"></div>
    </div>
  </section>

  <section class="view" id="view-system" hidden>
    <div class="card"><div class="card-h"><h2>Applications</h2></div><div class="card-b"><div class="apps" id="appList"></div></div></div>
    <div class="card"><div class="card-b flush"><div class="grid" style="grid-template-columns:1fr">
      <div class="cell" id="sysVol"><span class="k">Volume système</span><span class="val">—</span></div>
    </div></div></div>
    <div class="card"><div class="card-h"><h2>Disques</h2></div><div class="card-b" id="driveList"></div></div>
    <div class="card"><div class="card-h"><h2>Processus</h2><div class="tools"><button class="btn sm" id="procSort">Tri: mémoire</button><button class="btn sm" id="sysRefresh" aria-label="Actualiser">↻</button></div></div><div class="card-b flush" id="procList"></div></div>
  </section>

  <section class="view" id="view-terminal" hidden>
    <div class="card"><div class="card-h"><h2>Terminal</h2><div class="seg" style="width:148px;flex:none"><button data-shell="powershell" class="active">PS</button><button data-shell="cmd">CMD</button></div></div>
      <div class="card-b">
        <pre class="term" id="termOut"></pre>
        <form id="termForm" class="term-in"><input id="termIn" placeholder="Commande…" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="go"><button class="btn pri" type="submit" style="width:auto;padding:0 18px">Run</button></form>
        <button class="btn sm ghost" id="termClear" style="margin-top:12px">Effacer</button>
      </div>
    </div>
  </section>

  <nav class="nav">
    <button data-tab="home" class="active"><span class="ni">▦</span>Accueil</button>
    <button data-tab="screen"><span class="ni">▣</span>Écran</button>
    <button data-tab="files"><span class="ni">🗂</span>Fichiers</button>
    <button data-tab="system"><span class="ni">⚙</span>Système</button>
    <button data-tab="terminal"><span class="ni">›_</span>Terminal</button>
  </nav>
</main>

<dialog id="dlg"><div class="dlg" id="dlgBody"></div></dialog>
"""

PAGE = """<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,maximum-scale=1,user-scalable=no">
<meta name="theme-color" content="#09090b"><meta name="color-scheme" content="dark">
<meta name="mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent"><meta name="apple-mobile-web-app-title" content="PC Control">
<link rel="manifest" href="/manifest.webmanifest?v=11"><link rel="icon" type="image/svg+xml" href="/icon.svg?v=11"><link rel="apple-touch-icon" href="/icon-192.png?v=11">
<title>PC Control</title><style>__STYLE__</style></head><body>
<noscript><main style="padding:24px"><h1>PC Control</h1><p>JavaScript requis.</p></main></noscript>
__BODY__<script>__SCRIPT__</script></body></html>""".replace("__STYLE__", STYLE).replace("__BODY__", BODY).replace("__SCRIPT__", SCRIPT)

MANIFEST = {
    "name": "GTOL PC Control",
    "short_name": "PC Control",
    "description": "Pilotage complet et privé de la tour GTOL",
    "id": "/",
    "start_url": "/?app=11",
    "scope": "/",
    "display": "standalone",
    "display_override": ["standalone", "minimal-ui"],
    "orientation": "portrait",
    "background_color": "#09090b",
    "theme_color": "#09090b",
    "categories": ["utilities", "productivity"],
    "icons": [
        {"src": "/icon-192.png?v=11", "sizes": "192x192", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png?v=11", "sizes": "512x512", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png?v=11", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
    ],
    "shortcuts": [
        {"name": "Écran", "short_name": "Écran", "url": "/?app=11#screen"},
        {"name": "Terminal", "short_name": "Terminal", "url": "/?app=11#terminal"},
    ],
}

SERVICE_WORKER = r"""const CACHE="pc-control-v11";
self.addEventListener("install",e=>{self.skipWaiting()});
self.addEventListener("activate",e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
self.addEventListener("fetch",e=>{const r=e.request,u=new URL(r.url);if(r.method!=="GET"||u.pathname.startsWith("/api/"))return;
 e.respondWith(fetch(r,{cache:"no-store"}).catch(()=>caches.match(r).then(x=>x||new Response("Hors connexion",{status:503,headers:{"Content-Type":"text/plain;charset=utf-8"}}))))});
"""

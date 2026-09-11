// 刘海里的最小 Loom：只做「看回复 + 发消息」。状态与流事件走本机代理，
// token 不进 Atoll payload；网页本身从不插入动态状态，避免 descriptor 更新时
// 触发 WKWebView reload、吃掉正在输入的草稿。
//
// 协议语义参考 BeingAnywhere（MIT）：`POST /api/chat/stream` 的 SSE 优先直读，
// 服务端若只回 202，则按 `/api/stream/active?after=` 接续。这里不照搬浏览器扩展的
// 选词、侧栏或历史管理，只留下 Loom 对话真正需要的最小闭环。
//
// ⚠️ HTML 上限 20000 字节（`AtollWidgetWebContentDescriptor.isValid`）。

import Foundation

func chatHTML(port: UInt16, setupKey: String) -> String {
    template
        .replacingOccurrences(of: "{{PORT}}", with: String(port))
        .replacingOccurrences(of: "{{SETUP_KEY}}", with: setupKey)
}

private let template = #"""
<style>
:root{--loom-text:#e6edf3;--loom-muted:#7d8590;--loom-accent:#58a6ff;--loom-being:#3fb950;--loom-danger:#f85149}
*{box-sizing:border-box}
html,body{margin:0;width:100%;height:100%;overflow:hidden}
body{font-family:-apple-system,'SF Pro Text',system-ui;color:var(--loom-text)}
.shell{width:100%;height:100%;max-width:560px;margin:0 auto;display:flex;flex-direction:column;min-height:0}
.hidden{display:none!important}
#chat{position:relative;width:100%;height:100%;display:flex;flex-direction:column;min-height:0}
#gear{position:absolute;z-index:2;top:2px;right:7px;width:23px;height:23px;border:0;border-radius:8px;background:rgba(255,255,255,.07);color:var(--loom-muted);font-size:14px;cursor:pointer}
#log{flex:1;min-height:0;overflow-y:auto;padding:3px 36px 10px 8px;display:flex;flex-direction:column;gap:8px}
#log::-webkit-scrollbar{width:4px}
#log::-webkit-scrollbar-thumb{background:rgba(255,255,255,.16);border-radius:4px}
.m{max-width:88%;align-self:flex-start;padding:2px 0 2px 10px;border-left:2px solid rgba(63,185,80,.68);border-radius:2px;white-space:pre-wrap;word-break:break-word;font-size:13px;line-height:1.52;color:var(--loom-text)}
.m.you{max-width:78%;align-self:flex-end;padding:6px 9px;border:1px solid rgba(88,166,255,.32);border-radius:12px 12px 3px 12px;background:rgba(88,166,255,.11);box-shadow:inset 0 1px rgba(255,255,255,.055);color:var(--loom-text);text-align:left}
.m.error{padding-left:10px;border-left-color:var(--loom-danger);color:var(--loom-danger)}
.marker{align-self:stretch;padding:3px 0;color:var(--loom-muted);font-size:10px;text-align:center;opacity:.76}
.m.stream::after{content:'▍';margin-left:2px;color:#bc8cff;animation:blink 1s step-end infinite}
#activity{display:flex;align-items:center;gap:7px;min-height:18px;padding:0 10px 6px 18px;color:var(--loom-muted);font-size:11px;letter-spacing:.01em}
#activity i{width:6px;height:6px;border-radius:50%;background:#bc8cff;animation:pulse 1.2s ease-in-out infinite}
#composer{display:flex;align-items:flex-end;gap:7px;margin:0 6px 2px;padding:6px 7px 6px 11px;border:1px solid rgba(255,255,255,.12);border-radius:13px;background:rgba(255,255,255,.045)}
#in{flex:1;min-width:0;max-height:60px;resize:none;overflow-y:auto;border:0;outline:0;background:transparent;color:#e6edf3;font:13px/1.45 -apple-system,'SF Pro Text',system-ui;padding:2px 0}
#in::placeholder{color:#69717c}
#go{width:26px;height:26px;flex:0 0 26px;border:0;border-radius:50%;background:#e6edf3;color:#11151b;font-size:15px;line-height:1;cursor:pointer}
#go:disabled{opacity:.35;cursor:default}
#setup{height:100%;padding:11px 15px;display:flex;flex-direction:column;gap:7px;overflow-y:auto}
#setup p{margin:0;color:var(--loom-muted);font-size:12px;line-height:1.38}
#url{width:100%;border:1px solid rgba(255,255,255,.16);border-radius:9px;background:rgba(255,255,255,.055);color:var(--loom-text);font:12px/1.35 ui-monospace,SFMono-Regular,monospace;padding:7px 8px;outline:0}
#url:focus{border-color:rgba(88,166,255,.72)}
#url::placeholder{color:#69717c}
#setup-actions{display:flex;gap:7px;align-items:center}
#test,#save,#back{border:0;border-radius:8px;padding:6px 9px;font:12px -apple-system,'SF Pro Text',system-ui;cursor:pointer}
#test,#back{background:rgba(255,255,255,.10);color:var(--loom-text)}
#save{background:#e6edf3;color:#11151b;font-weight:600}
#setup-status{min-height:18px;font-size:11px;color:var(--loom-muted)}
#setup-status.ok{color:var(--loom-being)}
#setup-status.err{color:var(--loom-danger)}
@keyframes blink{50%{opacity:0}}
@keyframes pulse{0%,100%{opacity:.35;transform:scale(1)}50%{opacity:1;transform:scale(1.35)}}
@media (prefers-reduced-motion:reduce){#activity i,.m.stream::after{animation:none}}
</style>

<main class="shell">
  <section id="setup" class="hidden" aria-label="连接 Being">
    <button id="back" type="button" hidden>‹ 返回对话</button>
    <p>粘贴 Loom 中的完整 Being URL（含 token）。只保存在这台 Mac，Atoll 不会收到 token。</p>
    <input id="url" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="https://your-being-host/?token=…" aria-label="Being URL">
    <div id="setup-actions"><button id="test" type="button">测试连接</button><button id="save" type="button">保存并连接</button></div>
    <div id="setup-status" role="status"></div>
  </section>
  <section id="chat" class="hidden" aria-label="Soul 对话">
    <button id="gear" type="button" aria-label="设置 Being">⚙</button>
    <section id="log" aria-label="Soul 对话"></section>
    <div id="activity" hidden><i></i><span></span></div>
    <form id="composer"><textarea id="in" rows="1" maxlength="8000" placeholder="问 Soul…" aria-label="给 Soul 发消息"></textarea><button id="go" type="submit" aria-label="发送">↑</button></form>
  </section>
</main>

<script>
const API='http://127.0.0.1:{{PORT}}',SETUP_KEY='{{SETUP_KEY}}',setupHeaders={'X-Being-Notch-Setup':SETUP_KEY},log=document.getElementById('log'),input=document.getElementById('in'),go=document.getElementById('go'),activity=document.getElementById('activity'),setup=document.getElementById('setup'),chat=document.getElementById('chat'),urlField=document.getElementById('url'),testButton=document.getElementById('test'),saveButton=document.getElementById('save'),settingsStatus=document.getElementById('setup-status'),backButton=document.getElementById('back'),gear=document.getElementById('gear'),draftDelay=160;
const CATCH_UP_INITIAL_MS=2000,CATCH_UP_MAX_MS=30000,CATCH_UP_ABSOLUTE_MAX_MS=5*60*1000;
var busy=false,sessionId='',replyNode=null,replyText='',sawReply=false,sceneId='',historyBeingSignature='';
var draftTimer=null,draftEdited=false,configured=false;
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const nearEnd=()=>log.scrollHeight-log.scrollTop-log.clientHeight<56;
function scrollEnd(){log.scrollTop=log.scrollHeight}
function add(text,kind='being',follow=true){const stick=follow&&nearEnd(),node=document.createElement('article');node.className='m '+kind;node.textContent=text;log.append(node);if(stick)scrollEnd();return node}
function showActivity(text=''){activity.hidden=!text;activity.querySelector('span').textContent=text}
function resize(){input.style.height='auto';input.style.height=Math.min(Math.max(input.scrollHeight,24),60)+'px'}
function blurActiveElement(){const active=document.activeElement;if(active&&active!==document.body&&active!==document.documentElement&&typeof active.blur==='function')active.blur()}
function releaseWebFocus(){persistDraft();blurActiveElement()}
function showSetup(message='',kind=''){blurActiveElement();chat.classList.add('hidden');setup.classList.remove('hidden');backButton.hidden=!configured;setSettingsStatus(message,kind)}
function showChat(){blurActiveElement();setup.classList.add('hidden');chat.classList.remove('hidden')}
function setSettingsStatus(message='',kind=''){settingsStatus.textContent=message;settingsStatus.className=kind?' '+kind:''}
function setScene(data={}){const id=data&&data.scene_id,name=data&&data.name;if(typeof id==='string'&&id.startsWith('atoll-')){sceneId=id;return}if(typeof name==='string'&&name.trim()&&name!=="连接 Being")sceneId='atoll-'+name.trim()}
async function refreshScene(){try{const r=await fetch(API+'/state');if(r.ok)setScene(await r.json())}catch(_){} }
async function configure(save){const raw=urlField.value.trim();if(!raw){setSettingsStatus('请先粘贴完整 Being URL。','err');return}testButton.disabled=true;saveButton.disabled=true;setSettingsStatus(save?'正在保存并验证…':'正在验证…');try{const r=await fetch(API+(save?'/settings':'/settings/test'),{method:save?'PUT':'POST',headers:{...setupHeaders,'Content-Type':'application/json'},body:JSON.stringify({url:raw})}),data=await r.json().catch(()=>({}));if(!r.ok)throw Error(data.error||'无法连接 Being');if(!save){setSettingsStatus('已连接 '+data.name+'，现在可以保存。','ok');return}setScene(data);urlField.value='';configured=true;setSettingsStatus('已连接 '+data.name+'。','ok');setTimeout(async()=>{showChat();try{await loadHistory()}catch(e){add('暂时无法读取 Loom 历史。','error')}loadDraft().catch(()=>{})},180)}catch(error){setSettingsStatus(error.message||'无法连接 Being。','err')}finally{testButton.disabled=false;saveButton.disabled=false}}
async function boot(){try{const r=await fetch(API+'/settings',{headers:setupHeaders}),data=await r.json();configured=!!data.configured;setScene(data);if(!configured){showSetup('先连接你的 Being，再开始对话。');return}await refreshScene();showChat();await loadHistory();loadDraft().catch(()=>{})}catch(error){showSetup('暂时无法读取本机设置。','err')}}
function persistDraft(){if(draftTimer){clearTimeout(draftTimer);draftTimer=null}fetch(API+'/draft',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({draft:input.value}),keepalive:true}).catch(()=>{})}
function scheduleDraftSave(){if(draftTimer)clearTimeout(draftTimer);draftTimer=setTimeout(persistDraft,draftDelay)}
async function loadDraft(){const r=await fetch(API+'/draft');if(!r.ok)throw Error('无法读取草稿');const data=await r.json();if(!draftEdited&&!input.value&&typeof data.draft==='string'){input.value=data.draft;resize()}}
function messages(data){const list=Array.isArray(data)?data:(data.messages||data.items||[]);return Array.isArray(list)?list:[]}
function role(item){return item.role==='user'||item.role==='human'?'you':'being'}
function inMyScene(item){const sid=item&&item.scene_id;return !sceneId||!sid||sid===sceneId}
function isHistoryMarker(item){return !!item&&(item.from==='system'||item.type==='marker')}
function contentOf(item){return typeof item?.content==='string'?item.content:typeof item?.text==='string'?item.text:''}
function markerText(text){const raw=String(text||'').trim();if(raw.includes('breath yielded'))return '放下手头的事，转向你';if(raw.includes('interrupted'))return '已停止';if(raw.includes('superseded'))return '被新的对话取代';return raw.replace(/^\[|\]$/g,'')||'对话状态更新'}
function addMarker(text,follow=true){const stick=follow&&nearEnd(),node=document.createElement('div');node.className='marker';node.textContent=markerText(text);log.append(node);if(stick)scrollEnd();return node}
function historyKey(item,index){return [item.id||item.message_id||item.created_at||item.timestamp||index,item.role||item.from||'',contentOf(item)].join('\u001f')}
function beingSignature(list){return list.filter(x=>!isHistoryMarker(x)&&role(x)==='being').map(historyKey).join('\u001e')}
async function loadHistory(){const r=await fetch(API+'/history');if(!r.ok)throw Error('无法读取 Loom 历史');const data=await r.json(),list=messages(data).filter(inMyScene),signature=beingSignature(list),hasNewReply=!!historyBeingSignature&&signature!==historyBeingSignature;historyBeingSignature=signature;log.replaceChildren();list.slice(-12).forEach(x=>isHistoryMarker(x)?addMarker(contentOf(x),false):add(contentOf(x),role(x),false));scrollEnd();return hasNewReply}
function delta(data){const d=data&&data.delta;return typeof d?.text==='string'?d.text:typeof d==='string'?d:typeof data?.text==='string'?data.text:typeof data?.content==='string'?data.content:''}
function finishReply(data){if(data&&typeof data.session_id==='string')sessionId=data.session_id;if(replyNode){replyNode.classList.remove('stream');replyNode=null;replyText=''}}
function apply(type,data={}){
  if(type==='marker'){addMarker(delta(data)||data.message||'');return}
  if(type==='thinking'||type==='reasoning'){showActivity('Being 在思考');return}
  if(type==='tool_use'||type==='tool_result'){showActivity('Being 在行动');return}
  if(type==='content_block_delta'||type==='text'){showActivity('Being 在回复');const text=delta(data);if(!replyNode){replyNode=add('', 'being stream');replyText=''}if(text){const stick=nearEnd();replyText+=text;replyNode.textContent=replyText;if(stick)scrollEnd();sawReply=true}return}
  if(type==='message_stop'){finishReply(data);return}
  if(type==='error')throw Error(data.message||'Being 的回复中断')
}
function acceptsSceneEvent(type,data){return type==='meta'||type==='usage'||type==='error'||inMyScene(data)}
async function consume(body){
  if(!body)return false;const reader=body.getReader(),decoder=new TextDecoder();let pending='',type='',lines=[],accepted=false;
  const emit=()=>{if(!type){lines=[];return}let data={};try{data=JSON.parse(lines.join('\n')||'{}')}catch(e){}if(type==='meta'&&data.accepted)accepted=true;else if(acceptsSceneEvent(type,data))apply(type,data);type='';lines=[]};
  const line=value=>{if(!value){emit();return}if(value.startsWith(':'))return;const i=value.indexOf(':'),key=i<0?value:value.slice(0,i),raw=i<0?'':value.slice(i+1).replace(/^ /,'');if(key==='event')type=raw;if(key==='data')lines.push(raw)};
  while(true){const part=await reader.read();if(part.done)break;pending+=decoder.decode(part.value,{stream:true});const rows=pending.split(/\r?\n/);pending=rows.pop();rows.forEach(line)}
  pending+=decoder.decode();if(pending)line(pending);emit();return accepted;
}
async function followAccepted(){
  let cursor=0,delay=CATCH_UP_INITIAL_MS,deadline=Date.now()+CATCH_UP_ABSOLUTE_MAX_MS;
  while(Date.now()<deadline){
    const r=await fetch(API+'/active?after='+cursor);
    if(r.status===204){if(await loadHistory())return;await pause(delay);delay=Math.min(delay*2,CATCH_UP_MAX_MS);continue}
    if(!r.ok)throw Error('无法接续 Loom 回复');
    const active=await r.json(),events=Array.isArray(active.events)?active.events:[];
    for(const event of events){if(Number.isInteger(event.seq)&&event.seq>cursor)cursor=event.seq;const type=event.event||event.type,data=event.data||{};if(acceptsSceneEvent(type,data))apply(type,data)}
    if(active.finished){if(await loadHistory())return;await pause(delay);delay=Math.min(delay*2,CATCH_UP_MAX_MS);continue}
    await pause(events.length?220:Math.min(delay,1000));
  }
  await loadHistory()
}
async function send(){
  const raw=input.value,text=raw.trim();if(!text||busy)return;busy=true;go.disabled=true;sawReply=false;let delivered=false;add(text,'you');input.value='';persistDraft();resize();showActivity('正在发送');
  try{
    const body={message:text};if(sessionId)body.session_id=sessionId;if(sceneId)body.scene_id=sceneId;
    const r=await fetch(API+'/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});if(!r.ok)throw Error('发送失败');delivered=true;
    const accepted=await consume(r.body);if(accepted)await followAccepted();else if(!sawReply)await loadHistory();
  }catch(error){if(!delivered){input.value=raw;persistDraft();resize()}finishReply();add('⚠ '+(error.message||'发送失败'),'error')}
  finally{finishReply();busy=false;go.disabled=false;showActivity('')}
}
document.getElementById('composer').addEventListener('submit',e=>{e.preventDefault();send()});
input.addEventListener('input',()=>{draftEdited=true;resize();scheduleDraftSave()});input.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();send()}});
testButton.addEventListener('click',()=>configure(false));saveButton.addEventListener('click',()=>configure(true));gear.addEventListener('click',()=>showSetup());backButton.addEventListener('click',showChat);
// 草稿先落盘，再释放当前控件（包括按钮）的焦点。这样 Atoll 可以收回，
// 下一次展开时仍会从本机服务恢复未发送内容。
window.addEventListener('mouseleave',releaseWebFocus);
window.addEventListener('pagehide',persistDraft);
boot();resize();
</script>
"""#

const fs=require('node:fs'),assert=require('node:assert/strict'),{performance}=require('node:perf_hooks');
const path=require('node:path'),{execFileSync}=require('node:child_process'),os=require('node:os');
const root=path.resolve(__dirname,'../../..'),file='crates/ms-tooling/src/page.html';
const base=process.argv[2]||'37a14ba5797bed73a66d1350bee03d2238c63a20';
const page=execFileSync('git',['show',base+':'+file],{cwd:root,encoding:'utf8'});
const current=fs.readFileSync(path.join(root,file),'utf8');
const code=page.slice(page.indexOf('function route(){'),page.indexOf('const VIEWS='));
const make=c=>new Function('E','S','esc','empty',c+'return route;');
const changed=current.slice(current.indexOf('function route(){'),current.indexOf('const VIEWS='));
let checksum=0;const results=[];
for(const n of [100,10000,20000,40000]){const E={root:{name:'root',calls:[]},end:{name:'end',calls:[]}};for(let i=0;i<n;i++){E.root.calls.push('n'+i);E['n'+i]={name:'n'+i,calls:['end']}}const S={from:'root',to:'end'};const base=make(code)(E,S,String,()=>''),after=make(changed)(E,S,String,()=>'' );assert.equal(after(),base());const run=f=>{const t=performance.now(),s=f();checksum+=s.length;return performance.now()-t};for(let i=0;i<3;i++){run(base);run(after)}const samples={base:[],after:[]};for(let i=0;i<11;i++)for(const k of (i%2?['after','base']:['base','after']))samples[k].push(run(k==='base'?base:after));results.push({fanout:n,medianMs:Object.fromEntries(Object.entries(samples).map(([k,v])=>[k,v.slice().sort((a,b)=>a-b)[5]])),samples})}
console.log(JSON.stringify({baseline:base,node:process.version,cpu:os.cpus()[0].model,platform:os.platform()+' '+os.arch(),checksum,results},null,2));

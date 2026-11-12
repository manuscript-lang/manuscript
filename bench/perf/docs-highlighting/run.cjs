const fs=require('node:fs'),assert=require('node:assert/strict'),{performance}=require('node:perf_hooks');
const path=require('node:path'),{execFileSync}=require('node:child_process'),os=require('node:os');
const root=path.resolve(__dirname,'../../..'),base=process.argv[2]||'37a14ba5797bed73a66d1350bee03d2238c63a20';
const load=text=>{const module={exports:{}};new Function('module',text)(module);return module.exports};
const grammar=JSON.parse(fs.readFileSync(root+'/extensions/vscode/syntaxes/manuscript.tmLanguage.json','utf8'));
const file='website/assets/manuscript-highlight.js';
const baseline=load(execFileSync('git',['show',base+':'+file],{cwd:root,encoding:'utf8'})).tokenize;
const candidate=fs.readFileSync(path.join(root,file),'utf8');
const {prepareTokenizer:makeTokenizer}=load(candidate.replace('module.exports = { tokenize };','module.exports = { tokenize, prepareTokenizer };'));
const page=fs.readFileSync(root+'/documentation/core-language/types/named-types.md','utf8');
const ordinary=[...page.matchAll(/```(?:manuscript|ms)\n([\s\S]*?)```/g)].map(x=>x[1]);
const cases=[{name:'single-short',srcs:['x := 1\nprint(x)\n'],iterations:100},{name:'named-types-page',srcs:ordinary,iterations:10},{name:'single-long',srcs:['x := 1\nprint(x)\n'.repeat(1000)],iterations:4}];
let checksum=0;const results=[];const median=a=>a.slice().sort((a,b)=>a-b)[a.length>>1];
for(const {name,srcs,iterations} of cases){const f=makeTokenizer(grammar);for(const s of srcs)assert.deepEqual(f(s),baseline(s,grammar));
const run=k=>{const t=performance.now();for(let i=0;i<iterations;i++){const tok=k==='base'?s=>baseline(s,grammar):makeTokenizer(grammar);for(const s of srcs){const a=tok(s);checksum+=a.length+a.reduce((n,x)=>n+x.text.length,0)}}return (performance.now()-t)/iterations};
for(let i=0;i<10;i++){run('base');run('changed')}
const samples={base:[],changed:[]};for(let i=0;i<31;i++)for(const k of (i%2?['changed','base']:['base','changed']))samples[k].push(run(k));
results.push({name,fences:srcs.length,iterations,baseMs:median(samples.base),changedMs:median(samples.changed),pairedRatioMedian:median(samples.changed.map((x,i)=>x/samples.base[i])),samples});}
console.log(JSON.stringify({baseline:base,node:process.version,cpu:os.cpus()[0].model,platform:os.platform()+' '+os.arch(),checksum,results},null,2));

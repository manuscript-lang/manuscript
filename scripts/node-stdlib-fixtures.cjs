// Refresh offline path-oracle fixtures using the supported Node.js 24 baseline.
// Run from the repository root: node scripts/node-stdlib-fixtures.cjs
const fs=require('node:fs'),path=require('node:path');
if (Number(process.versions.node.split('.')[0]) !== 24) throw new Error('Use Node.js 24 to refresh compatibility fixtures');
const paths=['','.','..','/','//','///','a','a/','a//b','a/..','a/../','/a/../','/a//b/','foo.','.foo','..foo','a.tar.gz','.','...','/foo/.bar/','C:','C:/','C:foo','C:foo/..','C:\\foo\\bar\\','C:\\','\\foo','\\\\server\\share','\\\\server\\share\\','\\\\server\\share\\a','//server/share/a','a\\b','.\\a','\\\\?\\C:\\foo'];
const records=[];
for(const dialect of ['posix','win32']){
 const p=path[dialect],base=dialect==='posix'?'/work/project':'C:\\work\\project';
 for(const parts of [{root:'/',dir:'',base:'x.txt',ext:'.ignored',name:'ignored'},{root:'/',dir:'/a/',base:'x',ext:'',name:''},{root:'',dir:'relative',base:'',ext:'txt',name:'file'},{root:'C:\\',dir:'',base:'file',ext:'',name:''}])records.push({dialect,name:'format',args:[parts],expected:p.format(parts)});
 for(const value of paths)for(const suffix of ['','.txt','foo','share'])records.push({dialect,name:'basename_without',args:[value,suffix],expected:p.basename(value,suffix)});
 for(const value of paths){
  for(const name of ['normalize','basename','dirname','extname','isAbsolute','parse']) records.push({dialect,name,args:[value],expected:p[name](value)});
  // Pure Manuscript paths never consult ambient cwd or per-drive cwd.
  if(dialect==='posix'||value.startsWith('\\\\')||/^[A-Za-z]:[/\\]/.test(value)) records.push({dialect,name:'toNamespacedPath',args:[value],expected:p.toNamespacedPath(value)});
  if(!/^[A-Za-z]:[^/\\]/.test(value)) records.push({dialect,name:'resolve',args:[base,[value]],expected:p.resolve(base,value)});
 }
 if(dialect==='win32')for(const [base,parts] of [
  ['C:\\base',['D:\\other','C:child']],
  ['C:\\base',['D:unknown','C:\\final']],
  ['C:\\base',['D:\\other','\\rooted']],
  ['C:\\base',['C:child','..','tail']],
  ['\\\\server\\share\\base',['\\rooted','tail']],
  ['C:\\base',['D:\\other','C:child','C:leaf']],
 ])records.push({dialect,name:'resolve',args:[base,parts],expected:p.resolve(base,...parts)});
 for(const parts of [[],[''],['a','b'],['a','/b'],['/','/foo'],['//','server','share'],['C:','foo'],['C:\\','foo'],['a','..'],['a','b/']])records.push({dialect,name:'join',args:[parts],expected:p.join(...parts)});
 const absolute=dialect==='posix'?['/','/a','/a/b','/a/c','/other']:['C:\\','C:\\a','C:\\a\\b','C:\\a\\c','D:\\other','\\\\server\\share\\a'];
 for(const base of absolute)for(const target of absolute)records.push({dialect,name:'relative',args:[base,target],expected:p.relative(base,target)});
 for(const value of ['a.txt','b.js','x/a.txt','a/b/c.txt','.hidden','.x/a.txt','a1.js','a2.js','a3.js','a4.js','abab.txt','a/b.js','c/d.js','a01.js','a02.js','aa.js','ab.js','{literal}.js','b.txt'])for(const pattern of ['*.txt','**/*.txt','*.{txt,js}','a{1..3}.js','@(a|b).*','+(a|b).txt','?(a|b).txt','*(a|b).txt','!(a).txt','.*','[ab].*','{a/b,c/d}.js','a{01..03}.js','a{a..c}.js','[!a].txt','{literal}.js'])records.push({dialect,name:'matchesGlob',args:[value,pattern],expected:p.matchesGlob(value,pattern)});
}
fs.writeFileSync(path.join(__dirname,'../runtime/testdata/node-path.json'),JSON.stringify(records,null,2)+'\n');

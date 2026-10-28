from pathlib import Path
Path('methods').mkdir(exist_ok=True)
for count in (256,512,1024,2048):
    for mode in ('same','unique','nocall','field'):
        source=''
        for i in range(count):
            source+=f'type R{i}:\n    value: Int\n\n'
            name=f'read{i}' if mode=='unique' else 'read'
            if mode!='field':
                source+=f'impl R{i}:\n    def {name}() -> Int:\n        return self.value\n\n'
            value='x.value' if mode in ('field','nocall') else f'x.{name}()'
            source+=f'def get{i}(x: R{i}) -> Int:\n    return {value}\n\n'
        source+='export def main() -> Int:\n    return 0\n'
        Path(f'methods/{mode}-{count}.ms').write_text(source)

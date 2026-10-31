import csv
import json
from pathlib import Path
from statistics import median

out=Path(__file__).resolve().parent
contrasts=[('baseline','reverse'),('word','both'),('baseline','both'),('baseline','word'),('reverse','both')]
for suite,count in [('reverse',83),('normalize',100),('byte',220),('lines',16),('text',63)]:
    folder=out/(suite+'-matrix');record=json.loads((folder/'record.json').read_text());assert record['complete']
    rows=list(csv.DictReader((folder/'samples.csv').open()))
    labels=list(record['programs']);rounds=len(record['orders'])
    expected=json.loads((out/(suite+'-identities.json')).read_text());assert len(expected)==count
    assert len(rows)==count*len(labels)*rounds
    indexed={(r['case'],r['variant'],int(r['pair'])):r for r in rows};assert len(indexed)==len(rows)
    for name,identity in expected.items():
        for label in labels:
            for p in range(rounds):
                r=indexed[name,label,p]
                assert [int(r[k]) for k in ['input_bytes','iterations','checksum']]==identity
    result=[]
    for a,b in contrasts+([(a,'rust') for a in labels if a!='rust'] if 'rust' in labels else []):
        for name in expected:
            before=[int(indexed[name,a,p]['elapsed_ns'])/int(indexed[name,a,p]['iterations']) for p in range(rounds)]
            after=[int(indexed[name,b,p]['elapsed_ns'])/int(indexed[name,b,p]['iterations']) for p in range(rounds)]
            delta=[y-x for x,y in zip(before,after)]
            result.append({'suite':suite,'case':name,'before':a,'after':b,'rounds':rounds,
                           'before_median_ns':median(before),'after_median_ns':median(after),
                           'change_pct':100*(median(after)/median(before)-1),'paired_median_delta_ns':median(delta),
                           'paired_min_delta_ns':min(delta),'paired_max_delta_ns':max(delta),
                           'slower_pairs':sum(d>0 for d in delta),'before_min_ns':min(before),'before_max_ns':max(before),
                           'after_min_ns':min(after),'after_max_ns':max(after)})
    with (out/(suite+'-paired.csv')).open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(result[0]),lineterminator='\n');w.writeheader();w.writerows(result)
    print('\nSUITE',suite,'rows',len(rows))
    for a,b in contrasts[:3]:
        subset=[r for r in result if r['before']==a and r['after']==b]
        print(a+'->'+b,'increases',sum(r['change_pct']>0 for r in subset))
        for r in sorted(subset,key=lambda r:r['change_pct'],reverse=True)[:4]:
            print(r['case'],round(r['change_pct'],3),round(r['paired_median_delta_ns'],3),str(r['slower_pairs'])+'/'+str(r['rounds']),round(r['before_median_ns'],3),round(r['after_median_ns'],3))
    if suite=='reverse':
        for name in ['ascii_mixed_n63','ascii_mixed_n1048576','two_byte_copies65536','early_unicode_1048576']:
            for r in result:
                if r['case']==name and (r['before'],r['after']) in [('baseline','reverse'),('word','both'),('reverse','rust')]:print('GAIN',r)
    if suite=='text':
        for r in result:
            if r['before']=='baseline' and r['after']=='rust':print('RUST',r['case'],round(r['before_median_ns'],3),round(r['after_median_ns'],3),round(r['before_median_ns']/r['after_median_ns'],3),str(r['slower_pairs'])+'/'+str(r['rounds']))
rss=json.loads((out/'rss-results/record.json').read_text());assert rss['complete'];assert len(rss['samples'])==50
for mode in ['ascii','mixed']:
    for label in ['baseline','word','reverse','both','rust']:
        values=[s['metrics']['maxrss_kib'] for s in rss['samples'] if s['mode']==mode and s['label']==label]
        print('RSS',mode,label,values)

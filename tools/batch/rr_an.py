import json,glob,os,collections
os.chdir('/opt')
d=[l.strip().split('|') for l in open('drill_types.txt') if l.strip()]
names=[x[0] for x in d]
W=collections.defaultdict(lambda:[0,0])        # (a,b,field) -> [a wins, b wins]
K=collections.defaultdict(lambda:[0,0])        # (a,b,field) -> [a kills, a deaths]
for f in glob.glob('rr/*.txt'):
    red,blue,field=[x.replace('_',' ') for x in os.path.basename(f)[:-4].split('__')]
    s=[l for l in open(f) if l.startswith('SUMMARY')]
    if not s: continue
    j=json.loads(s[0][8:])
    kr=sum(j['kills'][0]); kb=sum(j['kills'][1])
    K[(red,blue,field)][0]+=kr; K[(red,blue,field)][1]+=kb
    K[(blue,red,field)][0]+=kb; K[(blue,red,field)][1]+=kr
    for bt in j['battles']:
        if bt['winner']==0: W[(red,blue,field)][0]+=1; W[(blue,red,field)][1]+=1
        elif bt['winner']==1: W[(blue,red,field)][0]+=1; W[(red,blue,field)][1]+=1
def agg(a,b=None,field=None):
    w=l=k=dth=0
    for (x,y,f),v in W.items():
        if x!=a or (b and y!=b) or (field and f!=field): continue
        w+=v[0]; l+=v[1]; k+=K[(x,y,f)][0]; dth+=K[(x,y,f)][1]
    return w,l,k,dth
for field in [None,'Open Plain','Walled Farm']:
    print('\n==',field or 'Both fields','| wins-losses | kills | deaths | K/D')
    rows=sorted(((agg(a,None,field),a) for a in names), key=lambda r:-r[0][0])
    for (w,l,k,dth),a in rows:
        print(f'{a:15s} {w:3d}-{l:<3d} {k:5d} {dth:5d}  {k/max(dth,1):5.2f}')
for who in ['Ninjas','Skirmishers','Militia','Sniper']:
    print('\n##',who,'vs each: OP w-l K/D | WF w-l K/D')
    for b in names:
        if b==who: continue
        o=agg(who,b,'Open Plain'); w=agg(who,b,'Walled Farm')
        print(f'  {b:15s} {o[0]}-{o[1]} {o[2]/max(o[3],1):4.2f} | {w[0]}-{w[1]} {w[2]/max(w[3],1):4.2f}')

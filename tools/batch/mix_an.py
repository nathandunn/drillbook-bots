import json,glob,os,collections
os.chdir('/opt')
d=[l.strip().split('|') for l in open('drill_types.txt') if l.strip()]
names=[x[0] for x in d]
MIX=json.load(open('mixes.json'))
R=collections.defaultdict(lambda:[0,0,0,0,0])   # (mix,opp,field) -> w,l,kills,deaths,battles
fields=set()
for f in glob.glob('mx/*.txt'):
    m,opp,field,side=[x.replace('_',' ') for x in os.path.basename(f)[:-4].split('__')]; side=int(side)
    s=[l for l in open(f) if l.startswith('SUMMARY')]
    if not s: continue
    fields.add(field)
    j=json.loads(s[0][8:]); o=1-side
    r=R[(m,opp,field)]
    r[2]+=sum(j['kills'][side]); r[3]+=sum(j['kills'][o]); r[4]+=j['matches']
    for bt in j['battles']:
        if bt['winner']==side: r[0]+=1
        elif bt['winner']==o: r[1]+=1
fields=sorted(fields)
def agg(m,opp=None,field=None):
    t=[0]*5
    for (a,b,f),v in R.items():
        if a!=m or (opp and b!=opp) or (field and f!=field): continue
        t=[x+y for x,y in zip(t,v)]
    return t
print('mix | all fields: w-l kills/b deaths/b K/D | ' + ' | '.join(f'{f}: w-l K/D' for f in fields))
for m in MIX:
    a=agg(m); row=f"{m:28s} {a[0]}-{a[1]} {a[2]/max(a[4],1):.1f} {a[3]/max(a[4],1):.1f} {a[2]/max(a[3],1):.2f}"
    for f in fields:
        x=agg(m,None,f); row+=f" | {x[0]}-{x[1]} {x[2]/max(x[3],1):.2f}"
    print(row)
print('\nhead to head, mix vs each drill (all fields): w-l K/D')
print(' '*28+''.join(n[:9].rjust(11) for n in names))
for m in MIX:
    row=''
    for n in names:
        a=agg(m,n); row+=f"{a[0]}-{a[1]} {a[2]/max(a[3],1):.1f}".rjust(11)
    print(m[:28].ljust(28)+row)

import json,glob,os,collections
os.chdir('/opt')
d=[l.strip().split('|') for l in open('drill_types.txt') if l.strip()]
names=[x[0] for x in d]
MIX=json.load(open('mixes.json'))
R=collections.defaultdict(lambda:[0,0,0,0,0])   # (mix,opp,field) -> w,l,kills,deaths,battles
for f in glob.glob('mx/*.txt'):
    m,opp,field,side=[x.replace('_',' ') for x in os.path.basename(f)[:-4].split('__')]; side=int(side)
    s=[l for l in open(f) if l.startswith('SUMMARY')]
    if not s: continue
    j=json.loads(s[0][8:]); o=1-side
    r=R[(m,opp,field)]
    r[2]+=sum(j['kills'][side]); r[3]+=sum(j['kills'][o]); r[4]+=j['matches']
    for bt in j['battles']:
        if bt['winner']==side: r[0]+=1
        elif bt['winner']==o: r[1]+=1
def agg(m,opp=None,field=None):
    t=[0]*5
    for (a,b,f),v in R.items():
        if a!=m or (opp and b!=opp) or (field and f!=field): continue
        t=[x+y for x,y in zip(t,v)]
    return t
print('mix | both: w-l kills/b deaths/b K/D | OP w-l K/D | WF w-l K/D')
for m in MIX:
    a=agg(m); o=agg(m,None,'Open Plain'); w=agg(m,None,'Walled Farm')
    print(f"{m:20s} {a[0]}-{a[1]} {a[2]/max(a[4],1):.1f} {a[3]/max(a[4],1):.1f} {a[2]/max(a[3],1):.2f} | {o[0]}-{o[1]} {o[2]/max(o[3],1):.2f} | {w[0]}-{w[1]} {w[2]/max(w[3],1):.2f}")
print('\nhead to head, mix vs each drill (both fields, of 8): w-l K/D')
print(' '*20+''.join(n[:9].rjust(11) for n in names))
for m in MIX:
    row=''
    for n in names:
        a=agg(m,n); row+=f"{a[0]}-{a[1]} {a[2]/max(a[3],1):.1f}".rjust(11)
    print(m[:20].ljust(20)+row)

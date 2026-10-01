import shlex, os, sys, json
G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
d=[l.strip().split('|') for l in open('drill_types.txt') if l.strip()]
MIX=json.load(open('mixes.json'))
os.makedirs(JOBS, exist_ok=True); i=0
for mname, mix in MIX.items():
    for opp,ot in d:
        for f in ["Open Plain","Walled Farm"]:
            for side in [0,1]:
                tag=f"{mname}__{opp}__{f}__{side}".replace(' ','_')
                a=[G,'--headless','--path','.','--','--sim=2','--seed=21','--cap=300',f'--field={f}']
                if side==0: a+= [f'--redmix={mix}', f'--blue={opp}', f'--bluetype={ot}']
                else: a+= [f'--bluemix={mix}', f'--red={opp}', f'--redtype={ot}']
                open(f'{JOBS}/{i:03d}.sh','w').write(' '.join(shlex.quote(x) for x in a)+f' > {shlex.quote(OUT+"/"+tag+".txt")} 2>&1\n'); i+=1
print(i)

import itertools, shlex, os, sys
G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
d=[l.strip().split('|') for l in open('drill_types.txt') if l.strip()]
os.makedirs(JOBS, exist_ok=True)
os.makedirs(OUT, exist_ok=True)
i=0
for (a,ta),(b,tb) in itertools.combinations(d,2):
    for f in ["Open Plain","Walled Farm"]:
        for red,rt,blue,bt in [(a,ta,b,tb),(b,tb,a,ta)]:
            tag=f"{red}__{blue}__{f}".replace(' ','_')
            args=[G,'--headless','--path','.','--','--sim=2',f'--red={red}',f'--redtype={rt}',f'--blue={blue}',f'--bluetype={bt}','--seed=21','--cap=300',f'--field={f}']
            open(f'{JOBS}/{i:03d}.sh','w').write(' '.join(shlex.quote(x) for x in args)+f' > {shlex.quote(OUT+"/"+tag+".txt")} 2>&1\n')
            i+=1
print(i)

M=/home/user/manuscript/target/release/ms
t(){ s=$(date +%s.%N); "$@" >/dev/null 2>&1; e=$(date +%s.%N); printf "%.1fs" $(echo "$e - $s" | bc); }
for n in "$@"; do
 echo "== n=$n"
 echo "ms release: $(t $M build p$n.ms -o ms_rel_$n)"
 echo "ms cranelift: $(MS_BACKEND=cranelift t $M build p$n.ms -o ms_cl_$n)"
 echo "ms debug: $(t $M build p$n.ms --build-type Debug -o ms_dbg_$n)"
 echo "rustc -O: $(t rustc -O p$n.rs -o rs_$n)"
 echo "rustc debug: $(t rustc p$n.rs -o rsd_$n)"
 echo "go: $(t go build -o go_$n p$n.go)"
 ls -l ms_rel_$n ms_cl_$n ms_dbg_$n rs_$n rsd_$n go_$n | awk '{print $5, $9}'
done

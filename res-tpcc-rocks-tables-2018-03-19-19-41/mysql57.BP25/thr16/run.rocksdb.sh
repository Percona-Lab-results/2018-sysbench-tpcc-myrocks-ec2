HOST="--mysql-socket=/tmp/mysql.sock"
#HOST="--mysql-host=127.0.0.1"
MYSQLDIR=/home/vadim/Percona-Server-5.7.21-20-Linux.x86_64.ssl100
DATADIR=/data/mysql
CONFIG=cnf/my-rocks.cnf

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

startmysql(){
  sync
  sysctl -q -w vm.drop_caches=3
  echo 3 > /proc/sys/vm/drop_caches
  ulimit -n 1000000
  numactl --interleave=all $MYSQLDIR/bin/mysqld --defaults-file=$CONFIG --basedir=$MYSQLDIR --user=root --rocksdb_block_cache_size=${BP}G --datadir=$DATADIR &
}

shutdownmysql(){
  echo "Shutting mysqld down..."
  $MYSQLDIR/bin/mysqladmin shutdown -S /tmp/mysql.sock
}

waitmysql(){
        set +e

        while true;
        do
                $MYSQLDIR/bin/mysql -Bse "SELECT 1" mysql

                if [ "$?" -eq 0 ]
                then
                        break
                fi

                sleep 30

                echo -n "."
        done
        set -e
}

initialstat(){
  cp $CONFIG $OUTDIR
  cp $0 $OUTDIR
}

collect_mysql_stats(){
  $MYSQLDIR/bin/mysqladmin ext -i10 > $OUTDIR/mysqladminext.txt &
  PIDMYSQLSTAT=$!
}
collect_dstat_stats(){
  vmstat 1 > $OUTDIR/vmstat.out &
  PIDDSTATSTAT=$!
}


# cycle by buffer pool size
RUNDIR=res-tpcc-rocks-tables-`date +%F-%H-%M`

#for BP in 100 90 80 70 60 50 40 30 20 10 5
BP=25
for tables in 10 5 3 2 1 
do

for i in 16
#for i in 1 2 4 8 16 32 64 128 256 512
do

#dyni -stop
echo "Restoring backup"
rm -fr /data/mysql
cp -r /data/mysql.rocksdb /data/mysql

startmysql &
sleep 10
waitmysql
#./start_dyno.sh &

#echo $(( $BP + 10 ))G > /sys/fs/cgroup/memory/DBLimitedGroup/memory.limit_in_bytes
#sync; echo 3 > /proc/sys/vm/drop_caches

#cgclassify -g memory:DBLimitedGroup `pidof mysqld`

runid="mysql57.BP$BP"

# perform warmup
#for i in  56

        OUTDIR=$RUNDIR/$runid/thr$i
        mkdir -p $OUTDIR

        # start stats collection
        initialstat
        collect_dstat_stats 


        time=3600
        ./tpcc.lua --mysql-socket=/tmp/mysql.sock --mysql-user=root --mysql-db=sbrocks --time=3600 --threads=$i --report-interval=1 --tables=$tables --scale=100 --use_fk=0 --db-driver=mysql --trx_level=RC  run |  tee -a $OUTDIR/res.txt

        # kill stats
        set +e
        kill $PIDDSTATSTAT
        set -e

        sleep 30
        shutdownmysql
done


done

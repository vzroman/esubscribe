BASEDIR=$(dirname $0)
cd ${BASEDIR}
erl -name master@host.com -eval 'c:c(esubscribe_test_callback), ct_master:run("./test.spec"), erlang:halt()' 
rm *.beam
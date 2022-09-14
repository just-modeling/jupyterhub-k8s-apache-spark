#!/bin/sh
# Loads environment variables to determine the correct JDBC driver to use.
source /etc/environment
# Quoting the label (i.e. EOF) with single quotes to disable variable interpolation.
cat << 'EOF' > /databricks/driver/conf/00-custom-spark.conf
[driver] {
    # Hive specific configuration options.
    # spark.hadoop prefix is added to make sure these Hive specific options will propagate to the metastore client.
    # JDBC connect string for a JDBC metastore
    "spark.hadoop.javax.jdo.option.ConnectionURL" = "jdbc:sqlserver://databricks-poc-v1-sql-server.database.windows.net:1433;database=ecae_metastore;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
    # Username to use against metastore database
    "spark.hadoop.javax.jdo.option.ConnectionUserName" = "ecae_admin@databricks-poc-v1-sql-server"
    # Password to use against metastore database
    "spark.hadoop.javax.jdo.option.ConnectionPassword" = "Simple123!"
    # Driver class name for a JDBC metastore
    "spark.hadoop.javax.jdo.option.ConnectionDriverName" = "com.microsoft.sqlserver.jdbc.SQLServerDriver"
    # Spark specific configuration options
    "spark.sql.hive.metastore.version" = "2.3.9"
    # Skip this one if <hive-version> is 0.13.x.
    "spark.sql.hive.metastore.jars" = "builtin"
    }
EOF
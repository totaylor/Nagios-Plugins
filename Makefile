#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# ===================
# bootstrap commands:

# Alpine:
#
#   apk add --no-cache git make && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make

# Debian / Ubuntu:
#
#   apt-get update && apt-get install -y git make && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make

# RHEL / CentOS:
#
#   yum install -y git make && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make

# ===================

ifneq ("$(wildcard bash-tools/Makefile.in)", "")
	include bash-tools/Makefile.in
endif

DOCKER_IMAGE := harisekhon/nagios-plugins

.PHONY: build
# space here prevents weird validation warning from check_makefile.sh => Makefile:40: warning: undefined variable `D'
build :
	@echo ====================
	@echo Nagios Plugins Build
	@echo ====================

	$(MAKE) init
	if [ -z "$(CPANM)" ]; then make; exit $?; fi
	$(MAKE) system-packages
	$(MAKE) perl-libs
	$(MAKE) python-libs
	@echo
	#$(MAKE) jar-plugins
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins)"

.PHONY: init
init:
	git submodule update --init

.PHONY: perl
perl:
	@echo ===========================
	@echo "Nagios Plugins Build (Perl)"
	@echo ===========================

	$(MAKE) init
	if [ -z "$(CPANM)" ]; then make perl; exit $?; fi
	$(MAKE) perl-libs

.PHONY: perl-libs
perl-libs:
	cd lib && make

	# XXX: there is a bug in the Readonly module that MongoDB::MongoClient uses. It tries to call Readonly::XS but there is some kind of MAGIC_COOKIE mismatch and Readonly::XS errors out with:
	#
	# Readonly::XS is not a standalone module. You should not use it directly. at /usr/local/lib64/perl5/Readonly/XS.pm line 34.
	#
	# Workaround is to edit Readonly.pm and comment out line 33 which does the eval 'use Readonly::XS';
	# On Linux this is located at:
	#
	# /usr/local/share/perl5/Readonly.pm
	#
	# On my Mac OS X Mavericks:
	#
	# /Library/Perl/5.16/Readonly.pm

	# Required to successfully build the MongoDB module for For RHEL 5
	#sudo cpan Attribute::Handlers
	#sudo cpan Params::Validate
	#sudo cpan DateTime::Locale DateTime::TimeZone
	#sudo cpan DateTime

	# You may need to set this to get the DBD::mysql module to install if you have mysql installed locally to /usr/local/mysql
	#export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:/usr/local/mysql/lib/"

	@#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	
	# add -E to sudo to preserve http proxy env vars or run this manually if needed (only works on Mac)
	
	which cpanm || { yes "" | $(SUDO_PERL) cpan App::cpanminus; }
	@echo
	# Workaround for Mac OS X not finding the OpenSSL libraries when building
	if [ -d /usr/local/opt/openssl/include -a \
	     -d /usr/local/opt/openssl/lib     -a \
	     `uname` = Darwin ]; then \
		 @echo "Installing Crypt::SSLeay with local openssl library locations"; \
	     yes "" | $(SUDO_PERL) sudo OPENSSL_INCLUDE=/usr/local/opt/openssl/include OPENSSL_LIB=/usr/local/opt/openssl/lib $(CPANM) --notest Crypt::SSLeay; \
	fi
	@echo
	@echo "Installing CPAN Modules"
	yes "" | $(SUDO_PERL) $(CPANM) --notest `sed 's/#.*//; /^[[:space:]]*$$/d;' setup/cpan-requirements.txt`
	@echo
	@bash-tools/perl_cpanm_install_if_absent.sh setup/cpan-requirements-packaged.txt
	
	# Fix for Kafka dependency bug in NetAddr::IP::InetBase
	#
	# This now fails with permission denied even with sudo to root on Mac OSX Sierra due to System Integrity Protection:
	#
	# csrutil status
	#
	# would need to disable to edit system InetBase as documented here:
	#
	# https://developer.apple.com/library/content/documentation/Security/Conceptual/System_Integrity_Protection_Guide/ConfiguringSystemIntegrityProtection/ConfiguringSystemIntegrityProtection.html
	#
	libfilepath=`perl -MNetAddr::IP::InetBase -e 'print $$INC{"NetAddr/IP/InetBase.pm"}'`; grep -q 'use Socket' "$$libfilepath" || $(SUDO_PERL) sed -i.bak "s/use strict;/use strict; use Socket;/" "$$libfilepath" || : # doesn't work on Mac right now
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins perl)"
	@echo
	@echo


.PHONY: python
python:
	@echo =============================
	@echo "Nagios Plugins Build (Python)"
	@echo =============================

	$(MAKE) init
	if [ -z "$(CPANM)" ]; then make perl; exit $?; fi
	$(MAKE) python-libs

.PHONY: python-libs
python-libs:
	cd pylib && make

	# newer version of setuptools (>=0.9.6) is needed to install cassandra-driver
	# might need to specify /usr/bin/easy_install or make /usr/bin first in path as sometimes there are version conflicts with Python's easy_install
	#$(SUDO) easy_install -U setuptools || $(SUDO_PIP) easy_install -U setuptools || :
	#$(SUDO) easy_install pip || :

	# fixes bug in cffi version detection when installing requests-kerberos
	$(SUDO_PIP) pip install --upgrade pip

	# only install pip packages not installed via system packages
	#$(SUDO_PIP) pip install --upgrade -r requirements.txt
	#$(SUDO_PIP) pip install -r requirements.txt
	@bash-tools/python_pip_install_if_absent.sh requirements.txt

	# cassandra-driver is needed for check_cassandra_write.py + check_cassandra_query.py
	# in requirements.txt now
	#$(SUDO_PIP) pip install cassandra-driver scales blist lz4 python-snappy

	# prevents https://urllib3.readthedocs.io/en/latest/security.html#insecureplatformwarning
	$(SUDO_PIP) pip install --upgrade ndg-httpsclient || $(SUDO_PIP) pip install --upgrade ndg-httpsclient

	#. tests/utils.sh; $(SUDO) $$perl couchbase-csdk-setup
	#$(SUDO_PIP) pip install couchbase
	
	# install MySQLdb python module for check_logserver.py / check_syslog_mysql.py
	# fails if MySQL isn't installed locally
	# Mac fails to import module, one workaround is:
	# sudo install_name_tool -change libmysqlclient.18.dylib /usr/local/mysql/lib/libmysqlclient.18.dylib /Library/Python/2.7/site-packages/_mysql.so
	# in requirements.txt now
	#$(SUDO_PIP) pip install MySQL-python
	
	# must downgrade happybase library to work on Python 2.6
	if [ "$$(python -c 'import sys; sys.path.append("pylib"); import harisekhon; print(harisekhon.utils.getPythonVersion())')" = "2.6" ]; then $(SUDO_PIP) pip install --upgrade "happybase==0.9"; fi

	@echo
	unalias mv 2>/dev/null; \
	for x in $$(curl https://api.github.com/repos/harisekhon/devops-python-tools/contents | jq '.[].name' | sed 's/"//g' | grep '^find_active_.*.py' ); do \
		wget -O $$x.tmp https://raw.githubusercontent.com/HariSekhon/devops-python-tools/master/$$x && \
		mv -vf $$x.tmp $$x; \
		chmod +x $$x; \
	done
	@echo
	bash-tools/python_compile.sh
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins python)"
	@echo
	@echo

# Net::ZooKeeper must be done separately due to the C library dependency it fails when attempting to install directly from CPAN. You will also need Net::ZooKeeper for check_zookeeper_znode.pl to be, see README.md or instructions at https://github.com/harisekhon/nagios-plugins
# doesn't build on Mac < 3.4.7 / 3.5.1 / 3.6.0 but the others are in the public mirrors yet
# https://issues.apache.org/jira/browse/ZOOKEEPER-2049
ZOOKEEPER_VERSION = 3.4.12
.PHONY: zookeeper
zookeeper:
	[ -x /sbin/apk ]        && $(MAKE) apk-packages || :
	[ -x /usr/bin/apt-get ] && $(MAKE) apt-packages || :
	[ -x /usr/bin/yum ]     && $(MAKE) yum-packages || :
	[ -f zookeeper-$(ZOOKEEPER_VERSION).tar.gz ] || wget -O zookeeper-$(ZOOKEEPER_VERSION).tar.gz "http://www.apache.org/dyn/closer.lua?filename=zookeeper/zookeeper-${ZOOKEEPER_VERSION}/zookeeper-${ZOOKEEPER_VERSION}.tar.gz&action=download" || wget -t 2 --retry-connrefused -O zookeeper-$(ZOOKEEPER_VERSION).tar.gz "https://archive.apache.org/dist/zookeeper/zookeeper-$(ZOOKEEPER_VERSION)/zookeeper-$(ZOOKEEPER_VERSION).tar.gz"
	[ -d zookeeper-$(ZOOKEEPER_VERSION) ] || tar zxf zookeeper-$(ZOOKEEPER_VERSION).tar.gz
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				./configure
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				$(SUDO) $(MAKE) install
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	perl Makefile.PL --zookeeper-include=/usr/local/include --zookeeper-lib=/usr/local/lib
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	LD_RUN_PATH=/usr/local/lib $(SUDO) make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	$(SUDO) $(MAKE) install
	perl -e "use Net::ZooKeeper"
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins perl zookeeper)"
	@echo
	@echo

.PHONY: jar-plugins
jar-plugins:
	@echo Fetching pre-compiled Java / Scala plugins
	@echo
	@echo Fetching Kafka Scala Nagios Plugin
	@echo fetching jar wrapper shell script
	# if removing and re-uploading latest this would get 404 and exit immediately without the rest of the retries
	#wget -c -t 5 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/blob/latest/check_kafka
	for x in {1..6}; do wget -c https://github.com/HariSekhon/nagios-plugin-kafka/blob/latest/check_kafka && break; sleep 10; done
	@echo fetching jar
	#wget -c -t 5 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/releases/download/latest/check_kafka.jar
	for x in {1..6}; do wget -c https://github.com/HariSekhon/nagios-plugin-kafka/releases/download/latest/check_kafka.jar && break; sleep 10; done

.PHONY: lib-test
lib-test:
	cd lib && $(MAKE) test
	rm -fr lib/cover_db || :
	cd pylib && $(MAKE) test

.PHONY: test
test: lib-test
	tests/all.sh

.PHONY: basic-test
basic-test: lib-test
	. tests/excluded.sh; bash-tools/all.sh
	tests/help.sh

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH and Nagios commands.cfg"

.PHONY: clean
clean:
	cd lib && $(MAKE) clean
	cd pylib && $(MAKE) clean
	@find . -maxdepth 3 -iname '*.py[co]' -o -iname '*.jy[co]' | xargs rm -f || :
	@$(MAKE) clean-zookeeper
	rm -fr tests/spark-*-bin-hadoop*

.PHONY: clean-zookeeper
clean-zookeeper:
	rm -fr zookeeper-$(ZOOKEEPER_VERSION).tar.gz zookeeper-$(ZOOKEEPER_VERSION)

.PHONY: deep-clean
deep-clean: clean clean-zookeeper
	cd lib && $(MAKE) deep-clean
	cd pylib && $(MAKE) deep-clean

#!/bin/sh

shell_quote_string() {
  echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage () {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is 1 src rpm will be built
        --build_source_deb  If it is 1 source deb package will be built
        --build_rpm         If it is 1 rpm will be built
        --build_deb         If it is 1 deb will be built
        --install_deps      Install build dependencies(root previlages are required)
        --branch            Branch from which submodules should be taken(default master)
        --help) usage ;;
Example $0 --builddir=/tmp/lib-dbd-mysql --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
  args="$args "`shell_quote_string "$1"`
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi
  
    for arg do
        val=`echo "$arg" | sed -e 's;^--[^=]*=;;'`
        optname=`echo "$arg" | sed -e 's/^\(--[^=]*\)=.*$/\1/'`
        case "$arg" in
            # these get passed explicitly to mysqld
            --builddir=*) WORKDIR="$val" ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_source_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --branch=*) DBD_BRANCH="$val" ;;
            --tpc_branch=*) TPC_BRANCH="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --help) usage ;;      
            *)
              if test -n "$pick_args"
              then
                  append_arg_to_args "$arg"
              fi
              ;;
        esac
    done
}

check_workdir(){
    if [ "x$WORKDIR" = "x$CURDIR" ]
    then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"
        then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}

add_percona_yum_repo(){
    if [ ${RHEL} == 7 || ${RHEL} == 8 ]; then
        if [ ! -f /etc/yum.repos.d/percona-dev.repo ]
        then
            wget http://jenkins.percona.com/yum-repo/percona-dev.repo
            mv -f percona-dev.repo /etc/yum.repos.d/
        fi
    fi
    yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
    percona-release enable ps-80 testing
    percona-release enable tools testing
    return
}

add_percona_apt_repo(){
  if [ ! -f /etc/apt/sources.list.d/percona-dev.list ]; then
    cat >/etc/apt/sources.list.d/percona-dev.list <<EOL
deb http://jenkins.percona.com/apt-repo/ @@DIST@@ main
deb-src http://jenkins.percona.com/apt-repo/ @@DIST@@ main
EOL
    sed -i "s:@@DIST@@:$OS_NAME:g" /etc/apt/sources.list.d/percona-dev.list
  fi
  wget -qO - http://jenkins.percona.com/apt-repo/8507EFA5.pub | apt-key add -
  wget https://repo.percona.com/apt/pool/testing/p/percona-release/percona-release_1.0-28.generic_all.deb
  #wget https://repo.percona.com/apt/percona-release_latest.generic_all.deb
  apt update
  apt-get install -y gnupg2
  #dpkg -i percona-release_latest.generic_all.deb
  dpkg -i percona-release_1.0-28.generic_all.deb
  percona-release enable ps-80 testing
  percona-release enable tools testing
  return
}

get_sources(){
    cd $WORKDIR
    if [ $SOURCE = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    git clone https://github.com/perl5-dbi/DBD-mysql.git perl-DBD-MySQL
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi
    mv $NAME $NAME-$VERSION
    cd $NAME-$VERSION
    if [ ! -z $DBD_BRANCH ]
    then
        git reset --hard
        git clean -xdf
        git checkout $BRANCH
    fi

    rm -f ${WORKDIR}/*.tar.gz
    #
    REVISION=$(git rev-parse --short HEAD)
    #
    git clone $PACKAGING_REPO packaging
    cp -r packaging/debian ./
    
    cd ${WORKDIR}

    echo "VERSION=${VERSION}" > perldbd.properties
    echo "REVISION=${REVISION}" >> perldbd.properties
    echo "RPM_RELEASE=${RPM_RELEASE}" >> perldbd.properties
    echo "DEB_RELEASE=${DEB_RELEASE}" >> perldbd.properties
    echo "GIT_REPO=${GIT_REPO}" >> perldbd.properties
    BRANCH_NAME="${BRANCH}"
    echo "BRANCH_NAME=${BRANCH_NAME}" >> perldbd.properties
    PRODUCT=perl-DBD-MySQL
    echo "PRODUCT=${PRODUCT}" >> perldbd.properties
    PRODUCT_FULL=${PRODUCT}-${VERSION}
    echo "PRODUCT_FULL=${PRODUCT_FULL}" >> perldbd.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> perldbd.properties
    echo "BUILD_ID=${BUILD_ID}" >> perldbd.properties
    #
    if [ -z "${DESTINATION}" ]; then
      export DESTINATION=experimental
    fi 
    #
    TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
    echo "DESTINATION=${DESTINATION}" >> perldbd.properties
    echo "UPLOAD=UPLOAD/builds/${PRODUCT}/${PRODUCT_FULL}/${BRANCH_NAME}/${REVISION}/${TIMESTAMP}" >> perldbd.properties
    #
    tar -zcvf ${NAME}-${VERSION}.tar.gz ${NAME}-${VERSION}
    
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $WORKDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf $NAME
    return
}

get_system(){
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    else
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}

install_deps() {
    if [ $INSTALL = 0 ]
    then
        echo "Dependencies will not be installed"
        return;
    fi
    if [ ! $( id -u ) -eq 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)
    if [ "x$OS" = "xrpm" ]
    then
        yum -y install git wget
        yum -y install epel-release rpmdevtools bison yum-utils percona-server-devel percona-server-server  perl-ExtUtils-MakeMaker perl-Data-Dumper gcc perl-DBI perl-generators openssl-devel
	yum -y install gcc-c++
	yum -y install perl-Devel-CheckLib
        add_percona_yum_repo
        if [ ${RHEL} == 8 || ${RHEL} == 9 ]; then
            yum -y install dnf-plugins-core
	    dnf module -y disable mysql
            #yum -y install epel-release
            if [ "x$RHEL" = "x8" ]; then
                yum config-manager --set-enabled PowerTools || yum config-manager --set-enabled powertools
                subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms
            fi
            yum -y install perl-Devel-CheckLib
            dnf clean all
            rm -r /var/cache/dnf
            dnf -y upgrade
            yum -y install openssl-devel rpmdevtools bison yum-utils percona-server-devel percona-server-server perl-ExtUtils-MakeMaker perl-Data-Dumper gcc perl-DBI perl-generators
            #yum -y install http://mirror.centos.org/centos/8/PowerTools/x86_64/os/Packages/perl-Devel-CheckLib-1.11-5.el8.noarch.rpm
	else
            until yum -y install centos-release-scl; do
                echo "waiting"
                sleep 1
            done
            yum -y install  gcc-c++ devtoolset-8-gcc-c++ devtoolset-8-binutils devtoolset-8-gcc devtoolset-8-gcc-c++
        fi
        cd $WORKDIR
        link="https://raw.githubusercontent.com/EvgeniyPatlan/perl-DBD-mysql-packaging/master/rpm/perl-DBD-MySQL.spec"
        wget $link
        yum-builddep -y $WORKDIR/$NAME.spec
    else
        add_percona_apt_repo
        apt-get update
        ENV export DEBIAN_FRONTEND=noninteractive
        DEBIAN_FRONTEND=noninteractive apt-get -y install devscripts equivs libdevel-checklib-perl libdbd-mysql-perl percona-server-server libperconaserverclient21-dev libssl-dev libtest-deep-perl libtest-deep-type-perl
        CURPLACE=$(pwd)
        cd $WORKDIR
        link="https://raw.githubusercontent.com/EvgeniyPatlan/perl-DBD-mysql-packaging/master/debian/control"
        wget $link
        cd $CURPLACE
        sed -i 's:apt-get :apt-get -y --allow :g' /usr/bin/mk-build-deps
        mk-build-deps --install $WORKDIR/control
        apt-get -y install ./libdbd-mysql-perl-build-deps_1.0_all.deb
    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'perl-DBD-MySQL*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'perl-DBD-MySQL*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}

get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR/source_deb -name "libdbd-mysql-perl*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "libdbd-mysql-perl*.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no sources for build"
            exit 1
        else
            cp $CURDIR/source_deb/$FILE $WORKDIR/
        fi
    else
        cp $WORKDIR/source_deb/$FILE $WORKDIR/
    fi
    return
}

build_srpm(){
    if [ $SRPM = 0 ]
    then
        echo "SRC RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    cd $WORKDIR
    get_tar "source_tarball"
    #
    rm -fr rpmbuild
    TARFILE=$(basename $(find . -name 'perl-DBD-MySQL-*.tar.gz' | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2"-"$3}')
    VERSION_TMP=$(echo ${TARFILE}| sed -e 's:_:.:' | awk -F '-' '{print $4}')
    VERSION=${VERSION_TMP%.tar.gz}
    #
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    cd ${WORKDIR}/rpmbuild/SPECS
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/packaging/rpm/*.spec' --strip=3
    cd ${WORKDIR}
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES/${NAME}-${VERSION_TMP}
    
    #
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .generic" rpmbuild/SPECS/*.spec
    #

    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    #

}

build_rpm(){
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
        exit 1
    fi
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'perl-DBD-MySQL*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'perl-DBD-MySQL*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR
    SRCRPM=$(basename $(find . -name '*.src.rpm' | sort | tail -n1))
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    mv *.src.rpm rpmbuild/SRPMS
    if [ -f /opt/rh/devtoolset-8/enable ]; then
        source /opt/rh/devtoolset-8/enable
    fi
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --rebuild rpmbuild/SRPMS/${SRCRPM}
    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
    
}

build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    rm -rf sysbench*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.gz *.changes
    #
    TARFILE=$(basename $(find . -name 'perl-DBD-MySQL-*.tar.gz' | sort | tail -n1))
    VERSION_TMP=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    OLD_VERSION=${VERSION_TMP%.tar.gz}
    VERSION=$(echo "$OLD_VERSION" | sed "s/_/\./")
    NEW_TAR=libdbd-mysql-perl-${VERSION_TMP}
    mv ${TARFILE} ${NEW_TAR}
    NAME=libdbd-mysql-perl
    rm -fr ${NAME}-${VERSION}
    #
    NEWTAR=${NAME}_${VERSION}.orig.tar.gz
    mv ${NEW_TAR} ${NEWTAR}
    
    tar xzf ${NEWTAR}
    mv perl-DBD-MySQL-${OLD_VERSION} ${NAME}-${VERSION}
    cd ${NAME}-${VERSION}
    dch -D unstable --force-distribution -v "${VERSION}-${DEB_RELEASE}" "Update to new upstream release perl-DBD-MySQL ${VERSION}-${DEB_RELEASE}"
    dpkg-buildpackage -S
    #
    cd ../
    mkdir -p $WORKDIR/source_deb
    mkdir -p $CURDIR/source_deb
    cp *_source.changes $WORKDIR/source_deb
    cp *.dsc $WORKDIR/source_deb
    cp *.orig.tar.gz $WORKDIR/source_deb
    cp *.tar.xz $WORKDIR/source_deb
    cp *_source.changes $CURDIR/source_deb
    cp *.dsc $CURDIR/source_deb
    cp *.orig.tar.gz $CURDIR/source_deb
    cp *.tar.xz $CURDIR/source_deb
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'changes' 'debian.tar.xz'
    do
        get_deb_sources $file
    done
    cd $WORKDIR
    rm -fv *.deb
    export DEBIAN_VERSION="$(lsb_release -sc)"
    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n 1))
    DIRNAME=$(echo ${DSC} | sed -e 's:_:-:' | sed -e 's:_:.:' | awk -F'-' '{print $1"-"$2"-"$3"-"$4}')
    VERSION=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $4}')
    ARCH=$(uname -m)
    #
    echo "ARCH=${ARCH}" >> perldbd.properties
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> perldbd.properties
    echo VERSION=${VERSION} >> perldbd.properties
    #
    dpkg-source -x ${DSC}
    cd ${DIRNAME}
    if [ "x${DEBIAN_VERSION}" = "xxenial" ]; then
        sed -i 's/libssl1.1/libssl1.0.0/' debian/control
    fi
    dch -b -m -D "$DEBIAN_VERSION" --force-distribution -v "1:${VERSION}-${DEB_RELEASE}.${DEBIAN_VERSION}" 'Update distribution'
    #
    dpkg-buildpackage -rfakeroot -uc -us -b
    mkdir -p $CURDIR/deb
    mkdir -p $WORKDIR/deb
    cp $WORKDIR/*.deb $WORKDIR/deb
    cp $WORKDIR/*.deb $CURDIR/deb
}

#main

CURDIR=$(pwd)
VERSION_FILE=$CURDIR/perldbd.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
SOURCE=0
TARBALL=0
OS_NAME=
ARCH=
OS=
DBD_BRANCH="4_050"
INSTALL=0
RPM_RELEASE=3
DEB_RELEASE=3
REVISION=0
PACKAGING_REPO="https://github.com/adivinho/perl-DBD-mysql-packaging.git"
NAME=perl-DBD-MySQL
parse_arguments PICK-ARGS-FROM-ARGV "$@"
VERSION=$DBD_BRANCH

check_workdir
get_system
install_deps
get_sources
build_srpm
build_source_deb
build_rpm
build_deb

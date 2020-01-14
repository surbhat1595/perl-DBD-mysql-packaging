Name:           perl-DBD-MySQL
Version:        4.050
Release:        4%{?dist}
Epoch:          1
Summary:        A MySQL interface for Perl
License:        GPL+ or Artistic
URL:            https://metacpan.org/release/DBD-mysql
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  gcc
BuildRequires:  percona-server-server
BuildRequires:  percona-server-devel
BuildRequires:  openssl-devel
BuildRequires:  perl-devel
BuildRequires:  perl-generators
BuildRequires:  perl-interpreter
BuildRequires:  perl(Carp)
BuildRequires:  perl(Config)
BuildRequires:  perl(Data::Dumper)
BuildRequires:  perl(DBI) >= 1.609
BuildRequires:  perl(DBI::DBD)
BuildRequires:  perl(Devel::CheckLib)
BuildRequires:  perl(DynaLoader)
BuildRequires:  perl(ExtUtils::MakeMaker)
BuildRequires:  perl(File::Basename)
BuildRequires:  perl(File::Copy)
BuildRequires:  perl(File::Path)
BuildRequires:  perl(File::Spec)
BuildRequires:  perl(Getopt::Long)
BuildRequires:  perl(strict)
BuildRequires:  perl(utf8)
BuildRequires:  perl(warnings)
BuildRequires:  zlib-devel
Requires:       perl(:MODULE_COMPAT_%(eval "`perl -V:version`"; echo $version))
Provides:       perl-DBD-mysql = %{epoch}:%{version}-%{release}

%{?perl_default_filter}

%description 
DBD::mysql is the Perl5 Database Interface driver for the MySQL database. In
other words: DBD::mysql is an interface between the Perl programming language
and the MySQL programming API that comes with the MySQL relational database
management system.

%prep

%setup -q -n %{name}-4_050

# Correct file permissions
find . -type f | xargs chmod -x

%build
perl Makefile.PL INSTALLDIRS=vendor OPTIMIZE="%{optflags}" NO_PACKLIST=1
make %{?_smp_mflags}

%install
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name '*.bs' -empty -delete
%{_fixperms} %{buildroot}/*

%check
# Full test coverage requires a live MySQL database
#make test

%files
%license LICENSE
%doc Changes README.md
%{perl_vendorarch}/Bundle/
%{perl_vendorarch}/DBD/
%{perl_vendorarch}/auto/DBD/
%{_mandir}/man3/*.3*

%changelog
* Tue Jan 14 2020 Evgeniy Patlan <evgeniy.patlan@percona.com> - 4.050-4
- Build with Percona Server as build dependency
use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojo::APNS',
  ABSTRACT_FROM => 'lib/Mojo/APNS.pm',
  VERSION_FROM => 'lib/Mojo/APNS.pm',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  LICENSE => 'perl',
  PREREQ_PM => {
    'IO::Socket::SSL' => 1.75,
    'Mojolicious' => '4.30',
  },
  BUILD_REQUIRES => {
    'Test::More' => '0.90',
  },
  META_MERGE => {
    resources => {
      license => 'http://dev.perl.org/licenses/',
      homepage => 'https://metacpan.org/release/Mojo-APNS',
      bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Mojo-APNS',
      repository => 'https://github.com/jhthorsen/mojo-apns',
    },
  },
  test => {
    TESTS => 't/*.t',
  },
);

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME => 'Mojo::APNS',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  VERSION_FROM => 'lib/Mojo/APNS.pm',
  PREREQ_PM => {
    'Mojolicious' => '4.00'
  },
  test => {
    TESTS => 't/*.t'
  },
);

eval '(exit $?0)' && eval 'exec perl -S $0 ${1+"$@"}' && eval 'exec perl -S $0 $argv:q'
        if 0;

#D \module
#D   [       file=mptopdf.pl,
#D        version=2000.05.29,
#D          title=converting MP to PDF,
#D       subtitle=\MPTOPDF,
#D         author=Hans Hagen,
#D           date=\currentdate,
#D            url=www.pragma-ade.nl,
#D      copyright={PRAGMA ADE / Hans Hagen \& Ton Otten}]
#C
#C This module is part of the \CONTEXT\ macro||package and is
#C therefore copyrighted by \PRAGMA. See licen-en.pdf for
#C details.

$program = "MPtoPDF 1.0" ;
$pattern = $ARGV[0] ;
$done    = 0 ;
$report  = '' ;

if (($pattern eq '')||($pattern =~ /^\-+(h|help)$/io))
  { print "\n$program: provide MP output file (or pattern)\n" ;
    exit }
elsif (-e $pattern)
  { @files = ($pattern) }
elsif ($pattern =~ /.\../o)
  { @files = glob "$pattern" }
else
  { $pattern .= '.*' ;
    @files = glob "$pattern" }

foreach $file (@files)
  { $_ = $file ;
    if (s/\.(\d+)$// && -e $file)
     { system ("pdftex \&mptopdf \\relax $file") ;
       rename ("$_.pdf", "$_-$1.pdf") ;
       if ($done) { $report .= " +" }
       $report .= " $_-$1.pdf" ;
       ++$done } }

if ($done)
  { print "\n$program: $pattern is converted to$report\n" }
else
  { print "\n$program: no filename matches $pattern\n" }

# first we get all the exisiting relationships in full so there are no duplicates
# then we process one file, upload it, and get its data.
# then we download the points, add them to the existing rels and loop.
use strict;
use warnings;
use Data::Dumper;
use LWP::Simple;
my %rels;



sub cacheFile
{
    my $uri=shift;
    my $file=shift;
    my $content = get $uri;
    mkdir "out" unless -d "out";
    open OUT,">out/$file";
    print OUT $content;
    close OUT;
}

sub getRel
{
    my $x=shift;

# have we seen it?
    if (!$rels{$x})
    {
	my $base="http://api.openstreetmap.org";
	my $uri = $base . "/api/0.6/relation/$x/full";
	warn $uri;
	$rels{$x}=$uri;
	cacheFile($uri,"Rel${x}.xml");
    }
}

sub load_rels
{
    my $file= "relationships.txt";

    open IN, $file;
    while (<IN>)
    {
	if (/^(\d+)/)
	{
	    getRel ($1);
	}
    }
    close IN;
}

#frist
load_rels;

warn Dumper(\%rels);

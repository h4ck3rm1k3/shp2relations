$count=1;

open OUT,">OUT_${count},txt";

while(<>)
{
    print OUT $_;

    if (/\/relation/)
    {
#warn $_;
	close OUT;
	$count++;
	open OUT,">OUT_${count},txt";
	warn "$count\n";
    }
}

close OUT;

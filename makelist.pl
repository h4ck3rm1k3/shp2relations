my $name="([\\wëćşçüžçöčđšëİ\-]+)";

while (<>)
{
    chomp;
    $_=lc($_);
    if (/^\w+/)
    {
	print "\n===$_===\n";
    }
    elsif (/^\s+\d+\s+${name}\s+${name}\s*$/i)

    {
#	print "debug:$_;";
	$x=ucfirst($1);
	$y=ucfirst($2);
	print "====$y $x====\n";
    }
    elsif (/^\s+\d+\s+${name}\s${name}\s+\d+\s${name}\s${name}\s*$/i)

    {
#	print "debug1:$_;\n";
#	print "debug2:$1 $2;\n";
#	print "debug3:$3 $4;\n";
	$x=ucfirst($1);
	$y=ucfirst($2);
	print "====$y $x====\n";
	$x=ucfirst($3);
	$y=ucfirst($4);
	print "====$y $x====\n";
    }


    elsif (/^\s*$/i)
    {}
    else
    {
	die "ERROR \"$_\"";
    }
    
}

use strict;
use warnings;
use Data::Dumper;
use Carp;

=head1

    1. empty ways
    2. double points in way
    3. 

=cut


my $tolerance=20;
my %nodes;
my %replace; # replace these ids with these
my %nodeids; # lookup the latlon of the nodes
my %nodesways; # what ways are these nodes used in
my %tags; # store the tags

my $newids = -3000000; # we give new objects ids starting here
my $current_way;
my $debug=1;
my %ways;
my %waystring;
# just store the last node seen an used that.
my $last_node_seen=0;
my %rels; # the relationships
#mapping of old ways onto new
my %waymapping;

##### we look for two in a row.. cannot have that
my %seenfilter;
my $QUOTE="[\\'\\\"]";
my %seen; # what have we emitted

=head2

new algorithm for removing duplicate way.

1. each segment is stored attached to the node. 
node has a list of in and out arcs each contain the from and two nodes
each arc contains the way(s) and relations(s) it belongs to.
if we find a duplicate segment, we can replace it immediatly.

=cut


my %ways_to_split;
my %node_arcs; 
# filled by add_arc_to_node, called by process_waynd


sub undup
{
    my $id=shift;
    if ($replace{$id})
    {
	my $new=$replace{$id};
	warn "adding replacing $id with $new in way $current_way\n" if $debug;
	$id=$new;	
    }
    return $id;
}


# sub characterize_way
# {			       
#     # split on each unique combination of the arcs.. we want fine cuttting   
#     # my $str= join (",",map {
#     #   if ($_->[2])
#     #     {
#     #       $lastway=$_->[2]; 
#     #     }
#     #   # transform the ways to relationships, 
#     #   die "no data" unless $_->[2];
#     #   my $rel1=$ways{$_->[2]}->{relationship} ;
#     #   my $rel2=$ways{$_->[3]}->{relationship} || $rel1 ;    
#     #   $rel1 .   "|"    . $rel2;    
#     # } (@{$node_arcs{$nd}}));    
# }


sub count_arcs_in_node
{
    my $n=shift;
    
    my $count =0;

    foreach my $i (@{$node_arcs{$n}})
    {
	if ($i->[3]) # to node
	{
	    $count++;
	}

	if ($i->[2]) # from node
	{
	    $count++;
	}
    }
    return $count;
}

sub add_arc_to_node
{
    my $from_nodeid=undup(shift);
    my $to_nodeid=undup(shift);
    my $in_way=shift;
    my $arc = [$from_nodeid,$to_nodeid,$in_way,0]; # the opposite way is null
    
    foreach my $n ($from_nodeid,$to_nodeid)
    {
	if ($node_arcs{$n})
	{
	    foreach my $i (@{$node_arcs{$n}})
	    {
		if ($from_nodeid == $i->[0]) # from node
		{
		    if ($to_nodeid == $i->[1]) # to node
		    {
			# match
			warn "duplicate tuple $from_nodeid -> $to_nodeid : in way" . $in_way . "\n" if $debug;

		    }
		}
		if ($from_nodeid == $i->[1]) # from node
		{
		    if ($to_nodeid == $i->[0]) # to node
		    {
			# match in the other direction
			$i->[3]=$in_way; # store the opposite direction
			warn "found opposite way $to_nodeid -> $from_nodeid : new way" . $in_way . " old way : ". $i->[2] if $debug;
			$ways_to_split{$i->[3]}=$i->[2];
#			return; dont return, we need the duplicate.
		    }
		}
	    }       
	}
	#add a node
    }
    push @{$node_arcs{$from_nodeid}},$arc;

}


sub make_new_way
{
    my $wayid =shift||die "no way id "; # old way

    my %seennd;
    my @newlist;
    map {if (!$seennd{$_}++){push (@newlist,$_);} } @_;  # all the new points to add 
    if (@newlist)
    {
	if ($#newlist <= 0)
	{
	    warn "cannot have only one or zero nodes in way" if $debug;
	}
	else
	{
	    $newids--; # allocate a new id for the way
	    push @{$ways{$newids}->{nodes}},@newlist;
	    push @{$waymapping{$wayid}},$newids; # map the old id onto the new
	    warn "new way $newids contains" . join (",",@{$ways{$newids}->{nodes}}) . "\n" if $debug;
	}
    }
    else
    {
	warn "Empty list $wayid called" if $debug;
    }

}


sub rotate_relation
  {
    my @relnodes=@_;
    my @neworder;

    while (@relnodes)
      {
	my $nd = shift @relnodes; # take one off the start

	push @neworder,$nd;
	
	my $arccount=count_arcs_in_node($nd);
	if ( $arccount > 2) # just take the length of the arcs
	  {
	    #stop
	    return (@relnodes,@neworder);
	  }

      }
    return @neworder;

  }

  
sub remove_duplicate_ways
{
    warn "remove_duplicate_ways\n" if $debug;
    # after we have looked at all the ways, we can remove the duplicates

    # the new side is on the left, the old side on the right.
    # we want to remove all the right side from the relations, add the left side to them
    # we do that by creating new ways from them, all the new ways will be references from the old for the purposes of making the relations
    # but first we need to split the side into the smallest common denominators
    # we look at a way, look at all the parts to it, see if the duplicate flag is set, and then split the way there.
    foreach my $rel (keys %rels)
    {
	my @relnodes; # an array of all nodes in the relationship
	my $lastway=0;

	## RESOLVE ALL RELATIONS, make one big array
	foreach my $wayid ( @{$rels{$rel}})
	{
	    warn "looking at $wayid \n" if $debug;
	    push @relnodes,@{$ways{$wayid}->{nodes}};
	    $lastway=$wayid;
	}

	warn "relation $rel had ". join (",",@relnodes). "\n" if $debug;
	# now rotate the relation until we find a point used by many 
	@relnodes=rotate_relation @relnodes;	

	warn "relation $rel has now ". join (",",@relnodes). "\n" if $debug;
	warn "last way is $lastway\n" if $debug;

#	my $rel =$ways{$wayid}->{relationship};
	my @newpoints=();
	my $count =0;
	my $length =scalar(@relnodes);
	my $lastnode=0;

	warn "relation $rel contains" . join (",",@relnodes) . "\n" if $debug;
	
	my $otherway="";	    
	while (@relnodes)
	{
	    my $nd = shift @relnodes; # take one off the start
	    my $arccount= count_arcs_in_node($nd); # just take the length of the arcs		
	    warn "node $nd has arcs $arccount\n" if $debug;
	    
	    if ($otherway eq "")
	    {
		$otherway=$arccount;
	    }
	    if ($arccount ne $otherway)
	    {
		warn "count($count) $arccount ne $otherway, going to make new way $rel contains" . join (",",@newpoints) . "\n" if $debug;
		if ($#newpoints < 1)
		{			  
		    warn "too few points" if $debug;
		}
		else
		{

		    # only add the other pint if the count is greater than 2
		    if ($arccount > 1)
		    {
			if (@newpoints)
			{
			    if ($newpoints[-1] ne $nd)
			    {
				push @newpoints,$nd;
			    }
			}
			else
			{
			    push @newpoints,$nd;
			}
		    }
		    elsif ($count == 0)
		    {
			push @newpoints,$nd; ## add in the first one anyway
		    }
		    else
		    {
			push @newpoints,$nd; ## add in the last one anyway!
		    }
		    
		    make_new_way(
			$lastway,
			(
			 @newpoints
			 #,$nd # add in the current node to close the way, but only on some.
			) 
			);
		    @newpoints=($nd); # add the last node to the first 		     
		    $otherway=""; #reset the checking
		}
		
	    } # str ne other way
	    
	    
	    ## add the new points after the decisions made
	    if (@newpoints)
	    {
		if ($newpoints[-1] ne $nd)
		{
		    push @newpoints,$nd;
		}
	    }
	    else
	    {
		push @newpoints,$nd; #first
	    }		
	    $count++;		
	    $lastnode=$nd; # save the last node
	    
	} #while
	
	warn "leftovers for rel:$rel lastway:$lastway   contains " . join (",",@newpoints) . "\n" if $debug;
	
	if ($#newpoints >0)
	{
	    # these leftovers should be tried to be combined with the rest of the nodes
		# have a situation where these nodes should be joined with the rest of the nodes.
	    make_new_way($lastway,@newpoints);	
	}
	
    } # each rel
    # then we add those parts to the new relations.
    
    
}

sub begin_way
{
    my $id=shift;
    $current_way = $id;
    warn "setting current way:$current_way" if $debug;
    $last_node_seen=0;
}

sub end_way
{
    warn "closing current way:$current_way" if $debug;
    warn "Way $current_way contains" . join (",",@{$ways{$current_way}->{nodes}}) . "\n" if $debug;

    $current_way=undef;
    $last_node_seen=0;
}

sub checksum
{
    my $lat=shift;
    my $lon=shift;
    my $checksum =(($lat + 180) *100000000000) + (($lon + 180) *1000000);
    return int($checksum);
}

sub post_process_way
{
    my $rel  =shift;
    my $wayid =shift || die carp "No way";
    if ($ways{$wayid}->{relationship})
    {
	die "way $wayid already in rel";
    }
    else
    {
	$ways{$wayid}->{relationship}=$rel;
    }
}

sub checkpair
{
    my $first=shift;
    my $second=shift;
    if ($first > $second)
    {
	my $t=$second;
	$second=$first;
	$first=$t;
    }
    if ($seenfilter{"${first}|${second}"}++)
    {
	warn "seen pair: first:${first} second:${second} skipping" if $debug;

	return 0;
    }
    return 1;
}

sub way_in_node
{
    my $way=shift;
    my $id=shift;
    my $isok=1;
    foreach my $chk (@{$nodesways{$id}})
    {
	if ($chk eq $way)
	{
	    return 1;
	}
    }
    return 0;
}

sub process_waynd
{
    my $id=shift;
    warn "process_waynd $id in way $current_way\n" if $debug;
    $id = undup ($id);

    # dont add duplicates in array
    # look if the nodesways(what ways are in this node)
    if (!way_in_node($current_way,$id))
    {
	# what whays is this node in
	warn "adding node:$id to way:$current_way\n" if $debug;
	push @{$nodesways{$id}},$current_way; # store the way in the node
    }    
    my $count = $#{$ways{$current_way}->{nodes}};
    if ($count < 0)
    {
	warn "Got count $count of nodes in $current_way\n" if $debug;
    }
    # done add duplicates to end of way
    if ($ways{$current_way}) # look up the current way
    {
#	my $lastinway=$last_node_seen;
	#my $lastinway=$ways{$current_way}->{nodes}[-1] || 0;
	# the first is missing
	my $lastitem = $ways{$current_way}->{nodes}[-1]; # the last item in the way
	
	if(!$lastitem)
	{
	    warn "lastitem is null for $current_way" if $debug;
#	    warn Dumper($ways{$current_way});
	    push (@{$ways{$current_way}->{nodes}},$id);# store the node     
	}
	else
	{
	    warn "last in way node :$lastitem in way:$current_way\n" if $debug;
	    if ($lastitem ne $id) # not the last in the way
	    {
		my $other=0;
			    
		# build up the new structure
		add_arc_to_node($lastitem, $id, $current_way);
		
		#  if (checkpair($lastinway, $id)) # remove all duplicate ways
		{
		    warn "in way $current_way adding pair lastitem:$lastitem, node:$id\n" if $debug;
		    
		    push (@{$ways{$current_way}->{nodes}},$id);# store the node     
		    
		    
		    # only store the last node seen if it is not a duplicate
		    $last_node_seen=$id;
		    
		}# if check pair

	    }
	} # 
    }
    else
    {
	warn "start new way: $current_way" if $debug;
	#start a new way
	push (@{$ways{$current_way}->{nodes}},$id);# store the node     
	warn "null :$current_way " . Dumper($ways{$current_way}) if $debug;
    }

#    $debug=0;
}

sub node
{
    my $id=shift;
    my $lat=shift;
    my $lon=shift;
    my $slat=sprintf("%0.${tolerance}f",$lat);
    my $slon=sprintf("%0.${tolerance}f",$lon);
    if ($nodes{$slat}{$slon})
    {
	my $old=$nodes{$slat}{$slon};	
	$replace{$id}=$old;
	return $old;
    }
    else
    {
	$nodes{$slat}{$slon}=$id;
	$nodeids{$id}=[$lat,$lon]; # store the nodes values
	return $id;
    }
}

sub consumeattrs
{
    if (s/timestamp=${QUOTE}[\d\-T:Z]+${QUOTE}//)
    {
	#remove timestable
    }
    
    if (s/changeset=${QUOTE}\d+${QUOTE}\s*//)
    {
	#remove changeset
    }
    if (s/uid=${QUOTE}\d+${QUOTE}\s?//)
    {}
    if (s/user=${QUOTE}[\w\s]+${QUOTE}\s*//)
    {
    }
    
    if (s/visible=${QUOTE}(true|false)${QUOTE}\s*//)
    {
	
    }
    
    if (s/action=${QUOTE}modify${QUOTE}\s*//)
    {
#	    warn "check $_" if $debug;
    }
    
    if (/action=${QUOTE}delete${QUOTE}/)
    {
	#next; # skip this
	return 0;
    }
    if (s/version=${QUOTE}\d+${QUOTE}\s*//)
    {
	#remove version
    }
    return 1;
#    warn "done $_" if $debug;
}

sub parse
{
    my $file=shift;
    open IN, $file or die;
    my $coordpattern = "-?[\\d\\.\\-Ee]+";
    my $QUOTE="[\\'\\\"]";
    my $lat=0;
    my $lon=0;
    my $current_rel=0;
    while (<IN>)
    {
	if (/<\?xml version=${QUOTE}1.0${QUOTE}/)  #encoding=${QUOTE}UTF-8${QUOTE}\?
	{
	}
	elsif (/<osm version=${QUOTE}0.\d${QUOTE}/) #generator=${QUOTE}[\w\s]+${QUOTE}>
	{
	}
	elsif (/<node/)
	{
	    next unless consumeattrs;
	    if (s/lon=${QUOTE}($coordpattern)${QUOTE} //)
	    {
		$lon=$1;
	    }
	    else
	    {
		die "no lon $coordpattern $_";
	    }
	    
	    if (s/lat=${QUOTE}($coordpattern)${QUOTE} //)
	    {
		$lat=$1;
	    }
	    else
	    {
		die "no lat $_";
	    }
	    
	    if (/<node id=${QUOTE}(-?\d+)${QUOTE}\s*\/?>/)
	    {
		node($1,$lat,$lon);
	    }
	    else
	    {	    
		die "Missing 2 $_";
	    }
	    
	}
	elsif (/<\/node/)
	{
	    #end of node
	}
	elsif (/\s*<way/){
#	consumeattrs;
	    next unless consumeattrs;
	    if (/\s*<way id=${QUOTE}(\-?\d+)${QUOTE}\s*>/)
	    {
		begin_way $1;	    
	    }
	    else
	    {
		die "missing way $_";
	    }
	}
	elsif(/<nd ref=${QUOTE}(-?\d+)${QUOTE}\s*\/>/)
	{
	    process_waynd($1);
	}
	elsif (/<\/way>/){
	    # end of way
	    end_way;
	}
#    <way id=${QUOTE}-572620${QUOTE} action=${QUOTE}modify${QUOTE} timestamp=${QUOTE}2010-12-05T01:31:40Z${QUOTE} visible=${QUOTE}true${QUOTE}>
	elsif (/<nd ref=${QUOTE}(-_\d)${QUOTE} \/>/){}
	elsif (/<relation/){
	    
#	consumeattrs;
	    next unless consumeattrs;
	    
	    if (/<relation id=${QUOTE}(\-?\d+)${QUOTE}\s*/)
	    {
		$current_rel=$1;
	    }
	    else
	    {
		die "Bad Relation $_";
	    }
	    # all on one line?
	    while (s/<member type=${QUOTE}way${QUOTE} ref=${QUOTE}(-?\d+)${QUOTE} role=${QUOTE}outer${QUOTE}\s?\/>//){
		
		# now we want to post process this way
		# cut the way on all the intersections with all other relations
		# remove other ways that are duplicate, match it 100%
		post_process_way($current_rel,$1); 
	    }
	}
	
	elsif (/<\/relation>/){
	    $current_rel=0;
	}
	elsif (/<member type=${QUOTE}way${QUOTE} ref=${QUOTE}(-?\d+)${QUOTE} role=${QUOTE}outer${QUOTE}\s?\/>/){
	    # now we want to post process this way
	    # cut the way on all the intersections with all other relations
	    # remove other ways that are duplicate, match it 100%
	    post_process_way($current_rel,$1); 
	}
	elsif (/<member type=${QUOTE}node${QUOTE} ref=${QUOTE}(-?\d+)${QUOTE} role=${QUOTE}admin_centre${QUOTE}\s?\/>/){}
	elsif (/<tag k=${QUOTE}(.+)${QUOTE} v=${QUOTE}(.+)${QUOTE}\s*\/>/)
	{
	    while (s/<tag k=${QUOTE}([^\/\${QUOTE}]+)${QUOTE} v=${QUOTE}([^\/\${QUOTE}]+)${QUOTE}\s*\/>//)
	    {
		if ($current_rel)
		{
		    $tags{$current_rel}{$1}=$2;
		}
		if ($current_way)
		{
		    $tags{$current_way}{$1}=$2;
		}
	    }
	}
	elsif (/<\/osm>/)
	{
	}
	elsif (/^\s+$/)
	{
	}
	else
	{
	    die "Missing anything $_";
	}
    }
    close IN;
}


=head2

    duplicate way algorithm

    1. each node has a pointer to a set of arc, the next node.
    2. if the next node points back to this node, it is duplicate, we remove it.

=cut

sub transfer_ways
{
    foreach my $wayid (sort keys %ways)
    {   
	my $rel =$ways{$wayid}->{relationship};
	if ($rel)
	{
	    # these relationships contains these ways
	    push @{$rels{$rel}},$wayid;###
	}
	else
	{
	    warn "no rel found, must be new" if $debug;
	    warn Dumper($ways{$wayid}) if $debug;
	}
    }	
}

sub emit_osm
  {
    my $ofile=shift;
    open OUT,">$ofile";

    #warn Dumper(\%waymapping); # dump out the ways 
    # now we can emit the relationships with the new ways instead of the old ones.
    #####################################################
    ### now output the doc 
    print OUT  "<osm version='0.6'>\n";
    foreach my $rel (keys %{rels}) {
      #    warn "emit $rel\n";
      #    warn Dumper($tags{$rel});
      #   warn Dumper($rels{$rel});
      my @ways;
      foreach my $oldway ( @{$rels{$rel}}) {
	warn "found old way $oldway" if $debug;

=head2
	    here we map all old ways onto new ways.
	    the old ways are not used, only the new ones, recreated from the old
	    the waymapping hash manages that

=cut

	foreach my $newway (@{$waymapping{$oldway}}	) {
	  # add the new ways
	  push @ways,$newway;
	  if (!$seen{$newway}++) {
	    warn "found new way $newway from old way $oldway" if $debug;
	    #		if (!$fail)
	    {
	      foreach my $nd (@{$ways{$newway}->{nodes}}) {
		# have we emitted the node yet?
		warn "$nd in $newway\n" if $debug;
			
		if (!$seen{$nd}++) {		    
		  my ($lat,$lon)=@{$nodeids{$nd}};
		  print OUT "<node id=\'$nd\' lat='$lat' lon='$lon'>\n".
		    "<tag k='_ID' v='$nd' />\n".
		      "</node>\n";
		}
			
	      }
	      # emit new way------------------------ 
	      print OUT "<way id='$newway'>\n";
	      foreach my $nd (@{$ways{$newway}->{nodes}}) {
		print OUT "<nd ref='$nd'/>\t";
	      }
	      print OUT "<tag k='is_in:country' v='Colombia'/>\n".
		"<tag k='_ID' v='$newway' />\n" .
		  "</way>\n";
	    }
	  } else {
	    #reusing the way
	  }
	}			## after all new ways
	
      }				# after old ways
      # relationships
      if (!$seen{$rel}++) {
	## emit the ways 
	print OUT "<relation id='$rel'>\n";
	foreach my $w (@ways) {
	  # emit the ways
	  print OUT "<member type='way' ref='$w' role='outer'/>\n";
	}	
	# keys
	foreach my $k (sort keys %{$tags{$rel}}) {
	  my $v=$tags{$rel}{$k};
	  print OUT "<tag k='$k' v='$v' />\n";
	}
	print OUT "<tag k='_ID' v='$rel' />\n";
	print OUT "</relation>\n";
      }
      # now emit the relationship
      #warn Dumper($tags{$rel});
    } # end of relationship
    print OUT "</osm>\n";
    close OUT;
  }

##################### MAIN ROUTINE TO CLEAN
  
  sub main
    {
      my $outfile=shift @_;
      
      foreach my $file (@_)
	{
	  parse $file;
	}

      
      transfer_ways;
      remove_duplicate_ways;
      emit_osm $outfile;
      
    };
    
    main @ARGV;

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
my %node_arcs; # filled by add_arc_to_node, called by process_waynd, while reading in, first pass


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



sub count_arcs_in_node_test
{
    my $n=shift;
    
    my $count =0;
    my %tways;
    foreach my $i (@{$node_arcs{$n}})
    {

	foreach my $j (2,3)
	{
	    my $x=$i->[$j];
	    if ($x) # to node
	    {
		if(!($tways{$x}++))
		{
		    $count+= abs($x);
		}
	    }
	}
    }
#    warn "node $n has $count arcs \n" if $debug;
#    warn Dumper($node_arcs{$n});

    return $count;
}


sub count_arcs_in_node2
{
    return count_arcs_in_node shift;
}

sub count_arcs_in_node
{
    my $n=shift;
    
    my $count =0;
    my %tways;
    foreach my $i (@{$node_arcs{$n}})
    {

#
#	foreach my $j (2,3)
	{
	    my $x=$i->[2] || "0";
	    my $y=$i->[3] || "0";
	    if(!($tways{$x . $y}++))
	    {
		$count++;
	    }
	}
    }
    warn "node $n has real count $count arcs \n" if $debug;
#    warn Dumper($node_arcs{$n}) if $debug;

    return $count;
}

sub append_node_to_way
{
    my $way_id=shift;
    my @nodes=@_;

    my $last = $ways{$way_id}->{nodes}->[-1] || 0; #could be empty return carp "no nodes to append!";
    my $first =$nodes[0] || return warn "no nodes in the list";

    my @newways = ($way_id);

    if ($waymapping{$way_id})
      {
#	push @newways, @{$waymapping{$way_id}};
	warn "newways ".  join(",",@newways);
      }

    foreach my $way_id (@newways)
      {

	if ($nodes[0] != $last)
	  {
	    warn "appending adding ". join (",",@nodes) . " to $way_id";
	    push @{$ways{$way_id}->{nodes}},@nodes;
	    report_way2 ($way_id);
	  }
	else
	  {
	    warn "ERROR: not appending ". join (",",@nodes) . " to $way_id";
	    report_way2 ($way_id);
	  }
      }

  }

sub prepend_node_to_way
{
    my $way_id=shift;
    my @nodes=@_;

    my @newways = ($way_id);

    if ($waymapping{$way_id})
      {
#	push @newways, @{$waymapping{$way_id}};
	warn "newways ".  join(",",@newways);
      }

    foreach my $way_id (@newways)
      {
	if ($nodes[-1] != $ways{$way_id}->{nodes}->[0])
	  {
	    warn "prepending adding ". join (",",@nodes) . " to $way_id";
	    unshift @{$ways{$way_id}->{nodes}},@nodes;
	    report_way2 ($way_id);
	  }
	else
	  {
	    warn "ERROR : not prepending ". join (",",@nodes) . " to $way_id";
	    report_way2 ($way_id);
	  }
      }

  }

sub add_arc_to_node # called by process_waynd, while reading in, first pass
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
			if ($i->[3]==0)
			{
			    $i->[3]=$in_way; # store the opposite direction

			    # now copy all the rows from the opposite to here 

			    warn "found opposite way $to_nodeid -> $from_nodeid : new way" . $in_way . " old way : ". $i->[2] if $debug;
			    $ways_to_split{$i->[3]}=$i->[2];

			}
			return; # return, we dont need the duplicate.
		    }
		}
	    }       
	}# if there are any arcs?
	else
	{
	     # we add on
	}
	#add a node
    }
    push @{$node_arcs{$from_nodeid}},$arc;
    push @{$node_arcs{$to_nodeid}},$arc; #add the other arc


}


sub lookup_waystring
{
#    my $id=shift;
    my @items=@_;
    my $str= join (",", sort @items);
    my $oldid=$waystring{$str};

#    if (!$oldid)
#    {
#	$oldid=$waystring{$str}=$id;
#    }
#    return 0;
    return $oldid;
}

sub save_waystring
{
    my $id=shift;
    my @items=@_;
    my $str= join (",", sort @items);
    my $oldid=$waystring{$str};

    if (!$oldid)
    {
	$oldid=$waystring{$str}=$id;

    }
   return $oldid;
}
my %reversed_strings;

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
	    warn "can have only one or zero nodes in way, we will connect them" if $debug;
	}
#	else
	{

	    # check for duplicates
	    my $oldid=lookup_waystring(@newlist);
	    if (!$oldid)
	    {
		$newids--; # allocate a new id for the way
		append_node_to_way ($newids,@newlist);
		push @{$waymapping{$wayid}},$newids; # map the old id onto the new
		warn "new way $newids contains" . join (",",@{$ways{$newids}->{nodes}}) . "\n" if $debug;

		save_waystring($newids,@newlist)
	    }
	    else
	    {
		warn "reusing old way $oldid" if $debug;
		$reversed_strings{$oldid}++;
		push @{$waymapping{$wayid}},$oldid; # map the old id onto the new
	    }
	}
    }
    else
    {
	warn "Empty list $wayid called" if $debug;
    }
    return $newids; # the new way
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
	      @neworder =(@relnodes,@neworder);
	      push @neworder,$neworder[0] unless $neworder[0]==$neworder[-1];
	      return @neworder;
	  }

      }

    if(@neworder)
    {
	push @neworder,$neworder[0] unless $neworder[0]==$neworder[-1];

    }

    return @neworder;

  }


sub report_way
{
    my $way=shift;
    my $a=@{$ways{$way}->{nodes}}[0];
    my $z=@{$ways{$way}->{nodes}}[-1];
    warn "report way $way starts at $a and ends at $z\n" if $debug;
}

sub report_way2
{
    my $way=shift;
    my $a=@{$ways{$way}->{nodes}}[0];
    my $z=@{$ways{$way}->{nodes}}[-1];
    my $str= join (",", @{$ways{$way}->{nodes}});
    warn "report way $way starts at $a and ends at $z\n details $str\n";
}

sub scan_prepend
{
    my $wayid=shift;
    my $node=shift;
}

sub scan_append
{
    my $wayid=shift;
    my $node=shift;
}

sub scan_attach # from find_connections
{
    my $wayid=shift;
    my $node=shift;

    foreach my $i (@{$node_arcs{$node}})
    {
	if ($wayid ==$i->[2])
	{
	    warn "check way A: $wayid  node $node and $i->[2]";
	}
	else
	{
	    if ($node==$i->[0])
	    {
		
		my @newways;
		if ($waymapping{$i->[3]})
		{
		    push @newways, @{$waymapping{$i->[3]}};
		    warn "newway2 ".  join(",",@newways);
		}
		if ($waymapping{$i->[2]})
		{
		    push @newways, @{$waymapping{$i->[2]}};
		    warn "newways ".  join(",",@newways);
		}
		my $found=0;
		foreach my $newway (@newways)
		{
		    if (($wayid ==$newway) && ($i->[3]) && (!$found))
		    {
			warn "append way B: $wayid  node $node and $i->[0]/$i->[1] to old way : $i->[2]";
#			warn Dumper($i);
			append_node_to_way($i->[2],$node);
			prepend_node_to_way($i->[3],$node);
			$found =1;			
		    }
		}
		
		if (!$found)
		{
		    warn "prepend way A: $wayid  node $node and $i->[0]/$i->[1] to old way : $i->[2]";
#		    warn Dumper($i);
		# now we prepend this node to that node 
		    prepend_node_to_way($i->[2],$node);

		    if ($i->[3])
		    {
			append_node_to_way($i->[3],$node);
		    }
		}

	    }
	    else
	    {
		
		warn "append way C: $wayid  node $node and $i->[0]/$i->[1] to old way : $i->[2]";
#		warn Dumper($i);
		append_node_to_way($i->[2],$node);
		if ($i->[3])
		{
		    prepend_node_to_way($i->[3],$node);
		}
	    }

	}
#	warn "check way $wayid  node $node and $i->[3]";

    }    
}

sub find_connections # from connect_way
{
    my $wayid =shift;
    
    # just scan all the other ways, if they have arcs then add them

    my $b=@{$ways{$wayid}->{nodes}}[0];
    my $e=@{$ways{$wayid}->{nodes}}[-1];    

    if ($b == $e)
    {
	scan_attach($wayid,$b);
    }
#    scan_prepend $wayid,$b;
#    scan_append  $wayid,$e;
}


sub connect_way
{

    my $prev=shift;
    my $next=shift;
    return unless $prev;
    return unless $next;

    find_connections $prev;
    find_connections $next;
    return;

    if ($reversed_strings{$prev})
    {
	if ($reversed_strings{$next})
	{
	    warn "REVERSED BOTH" if $debug;

	}
	else
	{
	    warn "REVERSED PREV" if $debug;
	}
	
    }
    else
    {
	if ($reversed_strings{$next})
	{
	    
	    warn "REVERSED NEXT" if $debug;
	}
	else
	{
	    warn "NOTHING REVERSED" if $debug;
	}
    }

    my $b=@{$ways{$prev}->{nodes}}[0];
    my $last=@{$ways{$prev}->{nodes}}[-1];
    my $first=@{$ways{$next}->{nodes}}[0];
    my $l=@{$ways{$next}->{nodes}}[-1];
    warn "checking if $prev ($b - $last) is connected to $next ($first - $l)\n" if $debug;
    if ($b == $last)
    {
	warn "repairing : prev is only one node, merge into the next\n" if $debug;

	append_node_to_way ($next,$last);
	report_way ($next);
    }
    elsif ($l == $first)
    {
	warn "repairing : next is only one node, merge into the prev\n" if $debug;

	append_node_to_way ($prev,$first);
	report_way ($prev);
    }
    elsif ($last == $first)
    {
	#OK
	warn "repairing : last $last == first $first\n" if $debug;
    }
    else
    {
	if ($b != $first)
	{
	    # now we decide which one do do depending on who has more connections
	    
	    my $first_c= count_arcs_in_node2($first); 
	    my $last_c = count_arcs_in_node2($last); 
	    
# first and last
	    warn "check_count $first has $first_c  and $last has $last_c\n" if $debug;
	    if ($first_c > $last_c)
	    {
		warn "repairing $prev ($b - $last) by appending $first to connect to $next ($first - $l)\n" if $debug;

		append_node_to_way ($prev,$first);
		report_way ($prev);
	    }
	    else
	    {
		warn "repairing connecting $prev ($b - $last) by prepending $last to the next way $next ($first - $l)\n" if $debug;

		prepend_node_to_way($next,$last);

		report_way ($next);
	    }
	}	    
    }


    # make sure the first item of the next way is the last of the prev
}

sub connect_way_loop
{
    my $prev=shift;
    my $next=shift;
    return unless $prev;
    return unless $next;
    my $b=@{$ways{$prev}->{nodes}}[0];
    my $last=@{$ways{$prev}->{nodes}}[-1];
    my $first=@{$ways{$next}->{nodes}}[0];
    my $l=@{$ways{$next}->{nodes}}[-1];

    if ($last == $first)
    {
	#OK
    }
    else
    {
	# if they originate from the same point, dont connect them

	warn "repairing loop $prev ($b - $last) by appending $first to connect to $next ($first - $l)\n" if $debug;

	append_node_to_way ($prev,$first);

    }    

    # make sure the first item of the next way is the last of the prev
}

  
sub remove_duplicate_ways # calls find_connections
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
	my $lastnewway=0; # the last new way created in this relation
	my $firstnewway=0;# the first one, it will be connected to the final one

	my @relnodes=(); # an array of all nodes in the relationship
	my $lastway=0;

	## RESOLVE ALL RELATIONS, make one big array
	foreach my $wayid ( @{$rels{$rel}})
	{
	    warn "looking at $wayid \n" if $debug;
	    die "$wayid has no nodes " unless @{$ways{$wayid}->{nodes}};
	    push @relnodes,@{$ways{$wayid}->{nodes}};

	    $lastway=$wayid;
	}
	die "no nodes " unless @relnodes;
	warn "relation $rel had ". join (",",@relnodes). "\n" if $debug;
	# now rotate the relation until we find a point used by many 
#	@relnodes=rotate_relation @relnodes;	

	warn "relation $rel has now ". join (",",@relnodes). "\n" if $debug;
	warn "relation $rel has now range:". join (",",$relnodes[0],$relnodes[-1]) . "\n" if $debug;
	warn "last way is $lastway\n" if $debug;

#	my $rel =$ways{$wayid}->{relationship};
	my @newpoints=();
	my $count =0;
	my $length =scalar(@relnodes);
	my $lastnode=0;

	warn "relation $rel contains" . join (",",@relnodes) . "\n" if $debug;
	
	my $otherway=0;
	while (@relnodes)
	{
	    my $nd = shift @relnodes; # take one off the start
	    my $arccount= count_arcs_in_node($nd); # just take the length of the arcs		
	    warn "node $nd has arcs $arccount\n" if $debug;
	    
	    if ($otherway ==0)
	    {
		$otherway=$arccount;
	    }
	    if ($arccount ne $otherway) #we split at any bunmps in the road
	    {
		warn "count($count) $arccount ne $otherway, going to make new way $rel contains" . join (",",@newpoints) . "\n" if $debug;
		
		$count++;	     
		push @newpoints,$nd;
		my $newway=make_new_way( $lastway, @newpoints	  );

		@newpoints = ($nd); # RESET and start with the last one!
		report_way($newway); # created new way

		if ($firstnewway ==0)
		{
		    warn "setting firstnew way $newway\n" if $debug;
		    $firstnewway=$newway; # record the first way created for final loop checking, all rels are closed
		}
		if ($lastnewway !=0) # if we are not at the first way, connect previous
		{
		  connect_way($lastnewway,$newway); # connect the end of the last new way to the begin of the new one
		}
		$lastnewway=$newway; # store the last way to glue them together 
		
	    } # has the properties of the ways changed?
	
	    
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

	    $lastnode=$nd; # save the last node
	    $otherway=$arccount;
	} #for each node in the relationship
	
	warn "leftovers for rel:$rel lastway:$lastway   contains " . join (",",@newpoints) . "\n" if $debug;
	
	if ($#newpoints >0)
	{
	    # these leftovers should be tried to be combined with the rest of the nodes
		# have a situation where these nodes should be joined with the rest of the nodes.
	    my $newway= make_new_way($lastway,@newpoints);	

	    warn "created final way";
	    report_way($newway); # created new way

	    connect_way($lastnewway,$newway); # connect the end of the last new way to the begin of the new one
	    
	    connect_way($newway,$firstnewway); # connect the end of the new way to the begin of the first

	    warn "rel $rel has $count parts\n";
	    if ($count ==0) # no ways split in the relation, it is a loop to itself
	    {
		warn "Rel $rel is connected to itself via way  $newway\n";
		connect_way_loop($newway,$newway); # connect the end of the new way to the begin of the first
	    }

	}

	# close the loop finally
	connect_way($lastnewway,$firstnewway); # connect the end of the last new way to the begin of the new one

	
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
# nodes is empty
	    append_node_to_way($current_way,$id)

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
		    append_node_to_way($current_way,$id);
		    # only store the last node seen if it is not a duplicate
		    $last_node_seen=$id;
		}# if check pair

	    }
	} 
    }
    else
    {
	warn "start new way: $current_way" if $debug;
	#start a new way
	append_node_to_way($current_way,$id);
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
    {    }
    if (s/visible=${QUOTE}(true|false)${QUOTE}\s*//)
    {    }
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

    warn  "Waymapping". Dumper(\%waymapping); # dump out the ways 
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

		  my $acount  =count_arcs_in_node($nd);
		  warn "$nd in $newway has $acount arcs\n" if $debug;

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

      transfer_ways; # fills out the rels list.
      remove_duplicate_ways;

      emit_osm $outfile;
      
    };
    
    main @ARGV;

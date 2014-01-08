#! /usr/bin/env perl

# use /usr/bin/perl in CYGWIN
my $MIN_HOURS = 12;
my $BRIEF = 1;
my %Data = ();
my %Cell = ();

my $StartDttm = undef;
my $EndDttm = undef;
our $brief_tm_audit_report=1;
$| = 1;

#################################################################
# This Script reads TM table dumped by aecqc.exp (1.13+) with -tmaudit option
# It will detect mismatch between RCP and CPP TM tables.
#
#  History:
#   v0.1 2013-Sep-11 by Ryan Liu
#     - Initial version
#   v0.9 2013-Sep-17 by Ryan Liu
#   v1.0 2013-Sep-19 
#     - Some bug fixes.
#     - Changing some logics according to PLM review comments. Thanks Kyle.
#   v1.1 2013-Nov-22 
#     - Bug fix: When data from two AECs are included in same input log, the output will be messed up
#     - Options to compare data with CPP, instead of RCP0-0
#   v1.2 2014-Jan-07 
#     - Bug fix: When data from two AECs are included in same input log, the output will be messed up
#     - Options to compare data with CPP, instead of RCP0-0

our $isDEBUG = 0; # false
our $VERSION = "1.2";

#print "testing -1\n";
############################
sub DEBUG
############################
{
        if ($isDEBUG eq 1) 
        {
                print (" DEBUG | ",@_, "\n")
        };
}

#################################################################
#       MAIN PROCEDURE
#################################################################
print ("tmparser.pl v$VERSION by Ericsson EEGS PLM (c) 2013\n");
	
# display help if no command-line parms
unless(@ARGV)
  { 
   &help;
   exit;
  }
my @FILES = @ARGV;
$TotalFiles = 0;
foreach my $file (@FILES) { $TotalFiles += 1; }

# my @FILES = @ARGV;
# or maybe   @FILES = glob("some/directory/*.ext");
my $processor = "";
my $su_id = -1;
my $sg_id = -1;
my $ha_state = "";
my $option = 0;       
my @SectorOnCnt; 
our %AEM2CPP;
our %AEMs;
our %CELL2CPP;
our %CELLMAP;

our %CELLNUMs9;  # Cell Number list for option 9
our %CELLNUMs12;  # Cell Number list for option 12
our %TMAEMALL; #stores TMAEMALL output
our $cellnum12;


foreach my $file (@FILES) 
{
    if($file eq '-v') # verbose
    {
        $brief_tm_audit_report = 0; 
		next; 
    }
    if($file eq '-d') # DEBUG mode
    {
        $isDEBUG = 1; 
		next; 
    }
	unless(open(INPUTFILE, "$file"))
		{ print "Cannot open a $file.\n"; exit;}
	print " Parsing $file\n";
	
	# Since in each patch, the menuItem number can be changed by designer. The actual expected menu 
	# item number will have to be detected from the menu. Following are the default menu item numbers.
	$menuItem_Dis_Cell_Map_All = 12;
	$menuItem_Dis_Cell_2_Cpp = 9;
	$menuItem_Dis_Alloc_CPP_Table =6;
	
	while ($eachLine = <INPUTFILE>)
	{
		# read the option number for  12. Dis_Cell_Map_All    : Display All Registerd Cell Map Table
		if($eachLine =~ /(\d+.)\s+Dis_Cell_Map_All\s+:/)
		{
			$menuItem_Dis_Cell_Map_All = $1;
		}
		
		# read the menu item number for Dis_Cell_2_Cpp Table
		if($eachLine =~ /(\d+.)\s+Dis_Cell_2_Cpp Table\s+:/)
		{
			$menuItem_Dis_Cell_2_Cpp = $1;
		}
	
 		# read the menu item number for Dis_Cell_2_Cpp Table
		if($eachLine =~ /(\d+.)\s+Dis_Alloc_CPP_Table\s+:/)
		{
			$menuItem_Dis_Alloc_CPP_Table = $1;
		}
 
		#chomp $eachLine;
		if($eachLine =~ /\[(\w\wP)(\d)\:(\d\d?)\(([A-Z]{3})\)\]tmaemall/)
		{
			$option = 77;  # tmaemall
			$processor = $1;
			$sg_id = $2;
			$su_id = $3;
			$ha_state = $4;
			DEBUG "option 77 detected!";
			next;
		}
		if($eachLine =~ /\[(\w\wP)(\d)\:(\d\d?)\(([A-Z]{3})\)\]tmaem/)
		{
			if ($1 != $processor || $2 != $sg_id || $3 != $su_id)
			{
				$processor = $1;
				$sg_id = $2;
				$su_id = $3;
				$ha_state = $4;
				$CELLMAP{$processor}{$sg_id}{$su_id}{"MaxChan"} = 0;
			}
			next;
		} 
		
		if($eachLine =~ /Enter Number\s?\(0 - \d{1,3}\) : (\d\d?)/ || $eachLine =~ /Enter Number : (\d\d?)/)
		{
			if ($1 != $option)
			{
				$option = $1;
				DEBUG ("   Option=$option Processor=$processor");
			}
			next;
		} 
		# tmaemall
		if (77 == $option)
		{
			if ( $eachLine =~ /(\[\s{1,3}(\d{1,4})\]\s{1,4}(\d{1,4})  (\d)\|\s?(\d\d?)\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}))\s{1,4}\d{1,4}\s\[\d\d\dd \d\dh \d\dm \d\ds\]\s+([A-Z_]{4,6})\s{6}\| [012-] [012-] [012-]\| [012-] [012-] [012-]\| [012-] [012-] [012-]\| [012-] [012-] [012-]\|/ )
			{
				DEBUG "proc=$processor aemid=$2 cell=$3 sg=$4 su=$5 ip=$6 op=$7";
				# TMAEMALL{aem_id} = "sg_id su_id"
				$TMAEMALL{$2}{"aemip"} = $6;
				$TMAEMALL{$2}{"cell"} = $3;
				$TMAEMALL{$2}{"sg"} = $4;
				$TMAEMALL{$2}{"su"} = $5;
				$TMAEMALL{$2}{"op"} = $7;
				
			}
		}
		
		# alloc_cpp table (AEM-CPP mapping)
		if ($menuItem_Dis_Alloc_CPP_Table == $option)
		{
			if ( $eachLine =~  /\[[AEDO]{2}M\s+(\d{1,3})\]  SG (\d) \/ SU\s\s?(\d\d?)/ )
			{
				$AEM2CPP{$processor}{$sg_id}{$su_id}{$1} = "$2.$3";
				#print " aem=$1\n";
				$AEMs{$1} ++;
			}
		}
	
		# cell 2 cpp mapping
		if ($menuItem_Dis_Cell_2_Cpp == $option)
		{
			if ( $eachLine =~  /\[CELL\s+(\d{1,4})\]  SG (\d) \/ SU (\d\d?)/ )
			{
				$CELL2CPP{$processor}{$sg_id}{$su_id}{$1} = "$2.$3";
				DEBUG (" $processor $sg_id $su_id cell-site $1  CPP $2.$3");
				$CELLNUMs9{$1} ++;
			}
		}
		# cell mapping (cell-channal-aemid)  Dis_Cell_Map_All from RCP
		if ( $menuItem_Dis_Cell_Map_All == $option )
		{
			if ( $eachLine =~ /Invalid Cell\(cell_idx:\d+, cell_number:(\d+)\)/ )
			{
				$cellnum12 = $1;
				$CELLNUMs12{$1} ++;
				$CELLMAP{$processor}{$sg_id}{$su_id}{$cellnum12}{0}{"band"} = "invalid";
				$CELLMAP{$processor}{$sg_id}{$su_id}{$cellnum12}{0}{"aem"} = "invalid";
				$CELLMAP{$processor}{$sg_id}{$su_id}{$cellnum12}{0}{"chan"} = "invalid";
				print "Invalid Cell $1\n";
			}
			if ( $eachLine =~  /={22} Cell\s{0,3}(\d{1,4})   Map Table ={23}/ )
			{
				$cellnum12 = $1;
				$CELLNUMs12{$1} ++;
				DEBUG "\n ---- cellnum12 = $cellnum12 --- \n";
				 
				next;
			}
			if ( $eachLine =~ /Index (\d) band_class     : (\d{1,2})/ )
			{
				$CELLMAP{$processor}{$sg_id}{$su_id}{$cellnum12}{$1}{"band"} = $2;
				DEBUG ("cellmap$processor$sg_id-$su_id $cellnum12 $1-band= [$2]");
				if ($CELLMAP{$processor}{$sg_id}{$su_id}{"MaxChan"} < $1) { 
					$CELLMAP{$processor}{$sg_id}{$su_id}{"MaxChan"} = $1; 
					DEBUG "max_chan = $CELLMAP{$processor}{$sg_id}{$su_id}{MaxChan}  |$processor|$sg_id|$su_id|";
					}
				
				next;
			}
			if ( $eachLine =~ /Index (\d) [doae]{2}m_idx        : (\d{1,4})/ )
			{
				$CELLMAP{$processor}{$sg_id}{$su_id}{$cellnum12}{$1}{"aem"} = $2;
				DEBUG "cellmap$processor$sg_id-$su_id-$cellnum12-$1-aem= [$2] ";
				if ($CELLMAP{$processor}{$sg_id}{$su_id}{"MaxChan"} < $1) { $CELLMAP{$processor}{$sg_id}{$su_id}{"MaxChan"} = $1; }
				next;
			}
			if ( $eachLine =~ /Index (\d) channel_number : (\d{1,4})/ )
			{
				$CELLMAP{$processor}{$sg_id}{$su_id}{$cellnum12}{$1}{"chan"} = $2;
				DEBUG "cellmap$processor$sg_id-$su_id-$cellnum12-$1-chan= " . $CELLMAP{$processor}{$sg_id}{$su_id}{$cellnum12}{$1}{"chan"} . "\n";
				if ($CELLMAP{$processor}{$sg_id}{$su_id}{"MaxChan"} < $1) { $CELLMAP{$processor}{$sg_id}{$su_id}{"MaxChan"} = $1; }
				next;
			}
		}

		if (10 == $option)
		# not finished yet.
		{
			if ($eachLine =~ /Input CELL Number\(0 ~ 4095\) : (\d{1,4})/)
			{
				DEBUG (" cell-site $1");
			}
			if ($eachLine =~ /Sector\((\d)\) : ([^\n]+)/)
			{
				if ( $SectorOnCnt[$1] > 0) 	{  DEBUG ("      $1 -- $2"); }
			}
			
			if ($eachLine =~ /op on cnt, Alpha:(\d), Beta:(\d), Gamma:(\d)/)
			{
				$SectorOnCnt[0] = $1;
				$SectorOnCnt[1] = $2;
				$SectorOnCnt[2] = $3;
			}
		}
		
		next;  # go to next line of file
	} #end of while eachLine
	
	next; # go to next file
}  # for each file

&validate_rcp_tm;
#&validate_cpp_tm;
&display_cellmap;
&display_cell2cpp;
&display_aem2cpp;

# -------------------------------
# Output data in table format

#chomp ($end_time = `date "+%m-%d %H:%M:%S"`);
#print("\n Script Start Time = $start_time\n   Script End Time = $end_time\n");

##############################################################################
sub help
{
 print <<END_HELP;
\n
TM Corruption Detection Script $VERSION by Ryan Liu EEGS PLM, Ericsson 2013/Sep/18
  This script parses the output captured by aecqc.exp with -tmaudit or -tmauditfull 
  options. It will compare TM tables between RCP and CPPs. A validation will also be done
  between TM tables within RCP.

Syntax: 
  tmparser.pl [-v] [-d] <files>

Options:
  -v      : Verbose mode. It provides details on all entries in the TM tables compared.
  -d      : Debug mode. 
  <files> : Input file(s). They can be output logs using aecqc.exp -tmaudit options, 
            or -tmauditfull options.
Maintained by BNET CDMA Access EEGS PLM.
(c) 2013

END_HELP
}


##############################################################################
sub progress
{
 # Display a progress message which will be overwritten by next progress call.
 my($msg) = @_;
 my $len = length($msg);

 # display new message
 print STDERR $msg;
 if($len < $LastProgLen)
   { print ' ' x ($LastProgLen - $len); }

 if($isDEBUG)
   { print STDERR "\n"; }
 else
   { 
    if($len < $LastProgLen)
      { print STDERR "\b" x $LastProgLen; }
    else
      { print STDERR "\b" x $len; }
   }

 $LastProgLen = $len;
}

# compare cell2cpp with tmaemall, aem2cpp with tmaemall (same as ER script)
sub validate_rcp_tm
{
	our %TMAEMALL;
	our %CELL2CPP;
	our %AEM2CPP;
	foreach $su(sort(keys(%{$AEM2CPP{RCP}{0}})))
	{
		$active_su = $su;
	}
	
	print "\n\n ======== RCP TM table validation ========\n";
	print " aemid| aemip           |  opSt  | cell | sg.su|CELL2CPP| AEM2CPP\n";
	print " -----+-----------------+--------+------+------+--------+----------\n";
	
	$Mismatches = 0;
	my $i=0;
	foreach $aemid (sort{$a <=> $b}(keys(%TMAEMALL)))
	{
		$mismatch = 0;
		$i++;
		$aemip = $TMAEMALL{$aemid}{"aemip"} ;
		$cell = $TMAEMALL{$aemid}{"cell"};
		$opSt = $TMAEMALL{$aemid}{"op"};
		$cppid = $TMAEMALL{$aemid}{"sg"} . "\." . $TMAEMALL{$aemid}{"su"};
		$cpp_cell2cpp = $CELL2CPP{RCP}{0}{$active_su}{$cell};
		$cpp_aem2cpp =  $AEM2CPP{RCP}{0}{$active_su}{$aemid};
		if($cppid ne $cpp_cell2cpp) 
		{
			if($opSt ne "INIT" || $cpp_cell2cpp ne "")
			{
				$cpp_cell2cpp .= "*"; 
				$mismatch=1;
			}
		};
		if($cppid ne $cpp_aem2cpp) 
		{
			if($opSt ne "INIT" || $cpp_aem2cpp ne "")
			{
				$cpp_aem2cpp .= "*";
				$mismatch=1;
			};
			
		}
		#if ($mismatch&& $opSt ne "INIT") {$Mismatches++};
		
		if (($brief_tm_audit_report && $mismatch) || !$brief_tm_audit_report) 
		{
			print (sprintf(" %4d | %15s | %6s | %4d | %-4s | %-5s  | %-5s \n",$aemid, $aemip, $opSt, $cell, $cppid, $cpp_cell2cpp, $cpp_aem2cpp));
		};
		
	}
	print " ------------------------------------------------------------------\n";
	print " Note: $Mismatches out of ",$i, " AEM(s) mismatched."; 
}

sub display_cellmap
{
	$aem = 0;
	my %active_su;
	my @service_unit_table;
	our %CELLMAP;
	our %CELLNUMs12;
	my $i=0;
	
	# displaying the Processor Name
	print " \n\n\n ======== Dis_Cell_Map_All(CELL-AEM/band/chan) ========        ";
	#foreach $proc (sort{$b <=> $a}(keys(%{$AEM2CPP{$aem}})))
	print "\n CELL ";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELLMAP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELLMAP{$proc}{$sg}})))
			{
				$service_unit_table[0][$i] = $proc;
				$service_unit_table[1][$i] = $sg;
				$service_unit_table[2][$i] = $su;
				print "|";
				if ($proc eq "RCP") { $active_su{$sg} = $su;}
				$i++;
				for ($j=1; $j<=$CELLMAP{$proc}{$sg}{$su}{"MaxChan"}; $j++)
				{
					print "            ";
				}
				print (sprintf("    %3s%1d-%-2d  ", $proc, $sg, $su));
				
			}
		}	
	}
	our $MAX_service_unit = $i;
	
	print "\n -----";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELLMAP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELLMAP{$proc}{$sg}})))
			{
				print "+-";
				for ($i=0; $i<=$CELLMAP{$proc}{$sg}{$su}{"MaxChan"}; $i++) 	{	print "------------";	}
			}
		}	
	}
	# displaying the content of cellmap
	print "\n";
	my $MismatchedAEMs=0;
	my $totalCell = 0;
	#foreach $aem (sort{$a <=> $b}(keys(%AEM2CPP)))
	foreach $cell (sort{$a <=> $b}(keys(%CELLNUMs12)))
	{
		$isMismatched = 0;
		$print_string = sprintf(" %4d ", $cell);
		for ($i=0; $i<$MAX_service_unit; $i++)
		{
			
			$proc = $service_unit_table[0][$i];# print "+$proc|";
			$sg = $service_unit_table[1][$i];
			$su = $service_unit_table[2][$i];
			#print " $proc $sg $su ";
			
			$Current_Value = "";
			for $index (sort(keys(%{$CELLMAP{$proc}{$sg}{$su}{$cell}})))
			{
				#print "index=$index";
				$band = $CELLMAP{$proc}{$sg}{$su}{$cell}{$index}{"band"};
				$aem  = $CELLMAP{$proc}{$sg}{$su}{$cell}{$index}{"aem"};
				$chan = $CELLMAP{$proc}{$sg}{$su}{$cell}{$index}{"chan"};
				
				$Current_Value = $Current_Value . "$aem/$band/$chan ";
			}
			
			$max_channels = $CELLMAP{$proc}{$sg}{$su}{"MaxChan"}+1; 
			$length = 12*$max_channels;
			
			$print_string .= sprintf("|%$length"."s", $Current_Value);
			
			$RCP_Value = "";
			for $index (sort(keys(%{$CELLMAP{RCP}{0}{$active_su{0}}{$cell}})))
			{
				#print "index=$index";
				$band = $CELLMAP{RCP}{0}{$active_su{0}}{$cell}{$index}{"band"};
				$aem  = $CELLMAP{RCP}{0}{$active_su{0}}{$cell}{$index}{"aem"};
				$chan = $CELLMAP{RCP}{0}{$active_su{0}}{$cell}{$index}{"chan"};
				#Ryan added here 2013/11/22 temporarily as we lost RCP data from field.
				#$band = $CELLMAP{CPP}{0}{0}{$cell}{$index}{"band"};
				#$aem  = $CELLMAP{CPP}{0}{0}{$cell}{$index}{"aem"};
				#$chan = $CELLMAP{CPP}{0}{0}{$cell}{$index}{"chan"};
				$RCP_Value = $RCP_Value . "$aem/$band/$chan ";
			}
			#print "RCP=$RCP_Value";
			if ($Current_Value ne $RCP_Value) 
			{
				$print_string .= "*";
				$isMismatched = 1;
			} else	{ $print_string .= " "}
			
			next;
		}
		if (($brief_tm_audit_report && $isMismatched) || !$brief_tm_audit_report) {print $print_string . "\n"}			
		if ($isMismatched) {$MismatchedAEMs++;}
		
		$totalCell++;
	}
	print " -----";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELLMAP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELLMAP{$proc}{$sg}})))
			{
				print "--";
				for ($i=0; $i<=$CELLMAP{$proc}{$sg}{$su}{"MaxChan"}; $i++) 	{	print "------------";	}
			}
		}	
	}

	print "\n Note: $MismatchedAEMs out of $totalCell cell(s) mismatched. \n";

}	


# ===============================================================================
#             CELL 2 CPP mapping Option 9
# ===============================================================================
sub display_cell2cpp 
{
	our %CELL2CPP;
	our $brief_tm_audit_report;
	my @service_unit_table;
	my $i=0;
	$Mismatches=0;
	# displaying the Processor Name
	print " \n\n ======== CELL 2 CPP mapping ========\n        ";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELL2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELL2CPP{$proc}{$sg}})))
			{
				print (sprintf("%3s   ",$proc));
				
				$service_unit_table[0][$i] = $proc;
				$service_unit_table[1][$i] = $sg;
				$service_unit_table[2][$i] = $su;
				$i++;
			}
		}	
	}
	our $MAX_service_unit = $i;
	print "\n CELL   ";
	# Displaying the SG/SU id
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELL2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELL2CPP{$proc}{$sg}})))
			{
				#print "$proc.$sg.$su\t";
				#sprintf("(%0.1f%).\n", ($sleepyAEMs/$totalAEMs)*100);
				print (sprintf("%1d-%-2d  ", $sg, $su));
				if ($proc eq "RCP") { $active_su{$sg} = $su;}
			}
		}
	}
	
	print "\n -------";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELL2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELL2CPP{$proc}{$sg}})))
			{
				print "------";
			}
		}	
	}
	# displaying the content of AEM-CPP table
	print "\n";
	my $Mismatches=0;
	my $totalCell = 0;
	foreach $cellnum (sort{$a <=> $b}(keys(%CELLNUMs9)))
	{
		#print sprintf(" %4d  ", $cellnum);
		$isMismatched = 0;
		$print_string = sprintf(" %4d  ", $cellnum);
		
		for ($i=0; $i<$MAX_service_unit; $i++)
		{
			$proc = $service_unit_table[0][$i];# print "+$proc|";
			$sg   = $service_unit_table[1][$i];
			$su   = $service_unit_table[2][$i];
			$Current_Value = $CELL2CPP{$proc}{$sg}{$su}{$cellnum};
			$RCP_Value     = $CELL2CPP{RCP}{0}{$active_su{0}}{$cellnum};
			# ryan adds here temporarily due to loss of RCP data from field
			$RCP_Value     = $CELL2CPP{CPP}{0}{0}{$cellnum};
			if ($Current_Value ne $RCP_Value) 
			{
				$Current_Value = $Current_Value . "*";
				$isMismatched = 1;
			} 
			$print_string .=( sprintf("%-5s|",$Current_Value) );
			#print( sprintf("%-4s ",$Current_Value) );
		}
		if (($brief_tm_audit_report && $isMismatched) || !$brief_tm_audit_report) {print $print_string . "\n"}
		if ($isMismatched) {$Mismatches++;}
		$totalCell++;
	}
	
	print " -------";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELL2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELL2CPP{$proc}{$sg}})))
			{
				print "------";
			}
		}	
	}
	
	print "\n Note: $Mismatches out of $totalCell CELL(s) mismatched.";
}



# ===============================================================================
#             AEM 2 CPP mapping Option 6
# ===============================================================================
sub display_aem2cpp
{
	our $brief_tm_audit_report;
	$aem = 0;
	my %active_su;
	my @service_unit_table;
	our %AEM2CPP;
	our %AEMs;
	my $i=0;
	
	# displaying the Processor Name
	print " \n\n\n ======== Dis_Alloc_CPP_Table(AEM-CPP) ========\n        ";
	#foreach $proc (sort{$b <=> $a}(keys(%{$AEM2CPP{$aem}})))
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$AEM2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$AEM2CPP{$proc}{$sg}})))
			{
				print (sprintf("%3s   ",$proc));
				
				$service_unit_table[0][$i] = $proc;
				$service_unit_table[1][$i] = $sg;
				$service_unit_table[2][$i] = $su;
				$i++;
			}
		}	
	}
	our $MAX_service_unit = $i;
	
	print "\n AEM    ";
	# Displaying the SG/SU id
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$AEM2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$AEM2CPP{$proc}{$sg}})))
			{
				print (sprintf("%1d-%-2d  ", $sg, $su));
				if ($proc eq "RCP") { $active_su{$sg} = $su;}
			}
		}	
	}
	print "\n -------";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$AEM2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$AEM2CPP{$proc}{$sg}})))
			{
				print "------";
			}
		}	
	}
	# displaying the content of AEM-CPP table
	print "\n";
	my $MismatchedAEMs=0;
	my $totalAem = 0;
	foreach $aem (sort{$a <=> $b}(keys(%AEMs)))
	{
		$isMismatched = 0;
		$print_string = sprintf("%4d   ", $aem);
		for ($i=0; $i<$MAX_service_unit; $i++)
		{
			$proc = $service_unit_table[0][$i];# print "+$proc|";
			$sg = $service_unit_table[1][$i];
			$su = $service_unit_table[2][$i];
			$Current_Value = $AEM2CPP{$proc}{$sg}{$su}{$aem};
			
			$RCP_Value = $AEM2CPP{RCP}{0}{$active_su{0}}{$aem};
			#Ryan added here 2013/11/22 temporarily as we lost RCP data from field.
			$RCP_Value = $AEM2CPP{CPP}{0}{0}{$aem};
			if ($Current_Value != $RCP_Value) 
			{
				$Current_Value = $Current_Value . "*";
				$isMismatched = 1;
			}
			$print_string .=( sprintf("%-5s|",$Current_Value) );
			
		}
		if (($brief_tm_audit_report && $isMismatched) || !$brief_tm_audit_report) {print $print_string . "\n"}
		if ($isMismatched) {$MismatchedAEMs++;}
		$totalAem++;
	}
	print " -------";
	foreach $proc (RCP,CPP)
	{
		foreach $sg (sort(keys(%{$CELL2CPP{$proc}})))
		{
			foreach $su(sort(keys(%{$CELL2CPP{$proc}{$sg}})))
			{
				print "------";
			}
		}	
	}
	
	print "\n Note: $MismatchedAEMs out of $totalAem AEM(s) mismatched. \n";

}	

# ===============================================================================
#             CELL MAP Table cell-chan-aemid Option 12 (RCP) or Option 14 (CPP)
# ===============================================================================

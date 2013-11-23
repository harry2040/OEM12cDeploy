#!/usr/bin/env perl
use strict;
use warnings;
use Net::OpenSSH;
use Crypt::Blowfish;
my $key = pack("H16","0123456789ABCDEF"); # Put your password file key here
my $cipher = new Crypt::Blowfish $key; 
my $username = "oracle";
my $cmd = "uname -a";
my $count = 0;
my $flag=0; #Variable to check if last password was ok.

# Host file
open (HOSTFILE, "hosts.dat") or die "Could not open host.dat because $!";

# Password File - Blowfish encyrpted
open (PASSWDFILE, "passsafe.dat") or die "Could not open pass.dat because $!";

# Open the log file
open (LOGFILE, "> logfile.dat") or die "Could not open logfile.dat because $!";

# Open the summary file
open (SUMFILE, "> sumfile.dat") or die "Could not open logfile.dat because $!";

# Open the Server_pass file - Use this if you want to generate a host,passwd file for future references instead of trying new passwords 
# open (SERVPASS, "> serv_pass.dat") or die "Could not open logfile.dat because $!";

# Loop the Hosts File
while (my $row = <HOSTFILE>) {
    #Bring the flag to reset
    $flag=0;
    # counter
    $count = $count + 1;
    
    chomp($row); #remove garbage characters at trailing or leading end.
    seek(PASSWDFILE,0,0); #move marker to first line of Password file
    print LOGFILE "-----------------------------------------------------------------\n";
    print LOGFILE "Server - $row\n";
    print SUMFILE "-----------------------------------------------------------------\n";
    print SUMFILE "$count. Server - $row\n";

     #Loop through the password file    
    while (my $epassword = <PASSWDFILE> and $flag==0) {
	# Get the decrypted password
	 my $password  = $cipher->decrypt($epassword);
	 my $ssh = Net::OpenSSH->new($row, user=>"oracle", passwd=>$password,strict_mode=>1, timeout => 10,kill_ssh_on_timeout => 1);
				
	if($ssh->error)
	{ 
	    
	    if (($ssh->error =~ m/password/) || ($ssh->error =~ m/timeout/))
	    {
		next;
	    }
	    else
	    {
		print LOGFILE $ssh->error."\n";
		last;
	    }
	}

	#If you are here it means that the password worked. Set the flag so that you skip to next host.
	$flag=1;
	 
	 #generate server password file- if you want to
	 #print SERVPASS $row . "," . $password;
	 #Get the Oracle home
	 my $cmd = "export DB_NAME=`ps -ef|grep pmon| grep -v grep| awk '{print \$8}'|cut -c10-\$NF|grep -v AS | sed 's/[1-3]\$//'` && grep -i \"^\$DB_NAME\" /etc/oratab | grep -v \"^#\" | grep -v \"^\*\"| grep \":\" | awk -F\":\" '{print \$2}'|uniq";
	 print LOGFILE $cmd;
	# Get Oracle Home
	my $ohome = $ssh->capture($cmd);
         print LOGFILE "Oracle home is ".$ohome;
	if ($ohome ne "")  # No Oracle_HOME, then get out!
	{
	    chomp($ohome);
	
	    $ssh->system('cd '.$ohome)
		or print LOGFILE "Error getting to oracle home directory" and last;
	    #inventory - Rip of the existing Agent home from inventory, this to overcome pre-requisites.
	    my $inventory = $ssh-> capture("cat /etc/oraInst.loc | grep -i inventory_loc | awk -F= '{print \$2}'");
	    print LOGFILE "Inventory found to be " . $inventory . "\n";
	    chomp($inventory);
	    
            #Strip out agent home information
	    my $inventory_file = $inventory . "/ContentsXML/inventory.xml";
	    my $inventory_bfile = $inventory . "/ContentsXML/inventory.xml_bak";
	    my $inventory_afile = $inventory . "/ContentsXML/inventory.agent";
	    print LOGFILE "Inventory file ". $inventory_file;
	    print LOGFILE "\nInventory backupfile". $inventory_bfile;
	    print LOGFILE "\nInventory agent file". $inventory_afile . "\n";

	    
            # Create backup of inventory file
	    $ssh->system('cp '.$inventory_file. ' '.$inventory_bfile)
		or print LOGFILE "Error backing up inventory file\n" and last;

	    #Strip the inventory agent details
	    my $cmd="awk \'BEGIN {IGNORECASE = 1; discard = 0;} \/\<HOME NAME=\"agent10g/ { discard = 1; next; } (discard == 1 && \/HOME/) { discard = 0; next; } (discard == 0) { print \$0; }\' " . $inventory_bfile . '  > ' .$inventory_file;
	    
	    
	    $ssh->system($cmd)
		or print LOGFILE "Error stripping agent inventory\n";
	    
	    print LOGFILE "Command to strip the inventory ". $cmd . "\n";

	    #Send stripped data to another file
	    $cmd="awk 'BEGIN {IGNORECASE = 1; discard = 0;} \/\<HOME NAME=\"agent10g/ { discard = 1; print \$0; next; } (discard == 1 && \/HOME/) { discard = 0; print \$0; next; } (discard == 1) { print \$0; }\' " . $inventory_bfile . ' > ' .$inventory_afile;
	   
	    $ssh->system($cmd)
		or print LOGFILE "Error stripping agent inventory to another file\n";
	    
	      print LOGFILE "Command to send the agent inventory to another file". $cmd . "\n";
	    

	    # Create directory for OEM 12c agent home
	    $cmd="mkdir -p ". $ohome . "/../../agent12c";
	   # print LOGFILE "Command is ". $cmd. "\n";
	    $ssh->system($cmd)
		or print LOGFILE "Error creating agent home directory" and last;
	    
	    #switch to new directory
	    $cmd="cd ". $ohome . "/../../agent12c";
	    #print LOGFILE "Command is ". $cmd."\n";
	    $ssh->system($cmd)
		or print LOGFILE "Error getting to agent home directory" and last;


	    my $ahome = $ssh->capture($cmd ."&& pwd"); # Get the Agent Oracle Home
	    print LOGFILE "Agent home is ". $ahome."\n";
	    chomp($ahome);

	    # Login to OEM 12c
	    print LOGFILE "Starting the OEM 12c part\n";
	    my $emcliop = `/app/oracle/Middleware12cr3/oms/bin/emcli login -username=MasterDBA -password=maximumSecurity 2>&1`;
	    print LOGFILE "Login result - ".$emcliop."\n"; 
	    if ($emcliop =~ m/successful/ )
	    {
		# Sync with repository
		$emcliop = `/app/oracle/Middleware12cr3/oms/bin/emcli sync`;
		print LOGFILE "Sync result - ".$emcliop."\n";
		if ($emcliop =~ m/successful/ )
		{
		    # Sumbit the push job
		    my $passfrag = substr $password, 0, 2;
		    print LOGFILE "Shredded Password - ". $passfrag."\n";
		    #Sumbit the job
		    my $emclicmd = "/app/oracle/Middleware12cr3/oms/bin/emcli submit_add_host -host_names=".$row." -platform=226 -port=3872 -installation_base_dir=".$ahome." -credential_name=DBA_".$passfrag." -session_name=\"Agent-".$row."\" -wait_for_completion";
		    print LOGFILE "Agent install command run is " .$emclicmd."\n";
		   
		   $emcliop = `$emclicmd`;
		   
		    print LOGFILE $emcliop;
		   
		    #get the job status
		    $emclicmd = "/app/oracle/Middleware12cr3/oms/bin/emcli get_add_host_status -session_name=\"Agent-".$row."\" -format=\"name:csv\" | awk -F, '{if(NR>3)print \$3,\$4,\$5,\$6}'";
		    print LOGFILE "Status Command run is " .$emclicmd."\n";
		    
		    $emcliop = `$emclicmd`;
		    
		    print LOGFILE $emcliop;
		   

		    if ($emcliop =~ /Succeeded Succeeded Succeeded/)
		    {
			print LOGFILE "All done! SUCCESS\n";
			print SUMFILE "All done! SUCCESS\n";
			 
		    }
		    else
		    {
			print LOGFILE "Error in installing the agent- DBA to intervene\n";
			print SUMFILE "Error in installing the agent - DBA to intervene\n"; 
			#restore the backup inventory file
			 $ssh->system('mv '. $inventory_file .' '. $inventory_file .'.script')
			     or print LOGFILE "Error moving existing inventory file for restore";
			 $ssh->system('cp '.$inventory_bfile. ' '.$inventory_file)
		        or print LOGFILE "Error restoring the inventory from backup file" and last;
		    }
		    #logout irrespective of success or failure
		    	$emclicmd = "/app/oracle/Middleware12cr3/oms/bin/emcli logout";
			$emcliop = `$emclicmd`;
			print LOGFILE "Logout result - ".$emcliop."\n"; 
		}
	    }
	}
    }
}


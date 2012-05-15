package Rebus::EDI::Vendor::Default;

# Copyright 2012 Mark Gavillet

use strict;
use warnings;

use parent qw(Exporter);
our @EXPORT  = qw(
  test
);

### Evergreen
our $edidir				=	"/tmp/";

### Koha
#our $edidir				=	"$ENV{'PERL5LIB'}/misc/edi_files/";

=head1 NAME

Rebus::EDI::Vendor::Default

=head1 VERSION

Version 0.01

=cut

our $VERSION='0.01';

sub new {
	my $class			=	shift;
	my $self			=	{};
	bless $self, $class;
	return $self;
}

sub parse_quote {
	my ($self, $quote)=@_;
	use Business::Edifact::Interchange;
	use Rebus::EDI;
	my $edi=Business::Edifact::Interchange->new;
	my @parsed_quote;
	$edi->parse_file($edidir.$quote->{filename});
	my $messages=$edi->messages();
	my $message_count=@{$messages};
	my $count;
	for ($count=0; $count<$message_count; $count++)
	{
		my $items=$messages->[$count]->items();
	
		foreach my $item (@{$items})
		{
			my $parsed_item	=	{
				author				=>	Rebus::EDI::cleanxml($item->author_surname).", ".Rebus::EDI::cleanxml($item->author_firstname),
				title				=>	Rebus::EDI::cleanxml($item->title),
				isbn				=>	Rebus::EDI::cleanxml($item->{item_number}),
				price				=>	Rebus::EDI::cleanxml($item->{price}->{price}),
				publisher			=>	Rebus::EDI::cleanxml($item->publisher),
				year				=>	Rebus::EDI::cleanxml($item->date_of_publication),
				item_reference		=>	Rebus::EDI::cleanxml($item->{item_reference}[0][1]),
				copies		=>		'',
			};
			my $quantity=$item->{quantity};
			my @copies;
			
			for (my $i=0; $i<$item->{quantity}; $i++)
			{
				my $copy_id=sprintf("%3d", ($i+1));
				$copy_id=~ tr/ /0/;
				my $copy_ref_num={id => $copy_id};
				push(@copies,$copy_ref_num);
			}

			foreach my $rel_num (@{$item->{related_numbers}})
			{
				my @segments=("LLO","LST","LSQ","LST","LFN","LCV");
				my $id = $rel_num->{id};
				$id=~ s/^0+//;
				$id--;
				foreach my $segment (@segments)
				{
					if ($rel_num->{$segment})
					{
						$id=~ s/^0+//;
						@copies->[$id-1]->{lc($segment)}=$rel_num->{$segment}->[0];
					}
				}
				@copies->[$id-1]->{shelfmark}=$item->shelfmark;
				my $ftxlin;
				my $ftxlno;
				if ($item->{free_text}->{qualifier} eq "LIN")
				{
					$ftxlin=$item->{free_text}->{text};
				}
				if ($item->{free_text}->{qualifier} eq "LNO")
				{
					$ftxlno=$item->{free_text}->{text};
				}
				my $note;
				if ($ftxlin)
				{
					@copies->[$id-1]->{note}=$ftxlin;
				}
				if ($ftxlno)
				{
					@copies->[$id-1]->{note}=$ftxlno;
				}
			}			
			$parsed_item->{"copies"}=\@copies;
			push (@parsed_quote,$parsed_item);
		}
	}
	return @parsed_quote;
}

sub create_order_message {
	my ($self, $order)=@_;
	my @datetime=localtime(time);
	my $longyear=($datetime[5]+1900);
	my $shortyear=sprintf "%02d",($datetime[5]-100);
	my $date=sprintf "%02d%02d",($datetime[4]+1),$datetime[3];
	my $hourmin=sprintf "%02d%02d",$datetime[2],$datetime[1];
	my $year=($datetime[5]-100);
	my $month=sprintf "%02d",($datetime[4]+1);
	my $linecount=0;
	my $segment=0;
	my $exchange=int(rand(99999999999999));
	my $ref=int(rand(99999999999999));
	
	### opening header
	my $order_message= "UNA:+.? '";
	
	### Library SAN or EAN
	$order_message	.= "UNB+UNOC:2";
	if (length($order->{org_san})!=13)
	{
		$order_message.="+".$order->{org_san}.":31B";			# use SAN qualifier
	}
	else
	{
		$order_message.="+".$order->{org_san}.":14";			# use EAN qualifier
	}
	
	### Vendor SAN or EAN
	if (length($order->{san_or_ean})!=13)
	{
		$order_message.="+".$order->{san_or_ean}.":31B";		# use SAN qualifier
	}
	else
	{
		$order_message.="+".$order->{san_or_ean}.":14";			# use EAN qualifier
	}
	
	### date/time, exchange reference number
	$order_message.="+$shortyear$date:$hourmin+".$exchange."++ORDERS+++EANCOM'";
	
	### message reference number
	$order_message.="UNH+".$ref."+ORDERS:D:96A:UN:EAN008'";
	$segment++;
	
	### Order number and quote confirmation reference (if in response to quote)
	if ($order->{quote_or_order} eq 'q')
	{
		$order_message.="BGM+22V+".$order->{order_id}."+9'";
		$segment++;
	}
	else
	{
		$order_message.="BGM+220+".$order->{order_id}."+9'";
		$segment++;
	}
	
	### Date of message
	$order_message.="DTM+137:$longyear$date:102'";
	$segment++;
	
	### Library Address Identifier (SAN or EAN)
	if (length($order->{org_san})!=13)
	{
		$order_message.="NAD+BY+".$order->{org_san}."::31B'";
		$segment++;
	}
	else
	{
		$order_message.="NAD+BY+".$order->{org_san}."::9'";
		$segment++;
	}
	
	### Vendor address identifier (SAN or EAN)
	if (length($order->{san_or_ean})!=13)
	{
		$order_message.="NAD+SU+".$order->{san_or_ean}."::31B'";
		$segment++;
	}
	else
	{
		$order_message.="NAD+SU+".$order->{san_or_ean}."::9'";
		$segment++;
	}
	
	### Library's internal ID for Vendor
	$order_message.="NAD+SU+".$order->{provider_id}."::92'";
	$segment++;
	
	### Lineitems
	foreach my $lineitem (@{$order->{lineitems}})
	{
		use Rebus::EDI;
		use Business::ISBN;
		$linecount++;
		my $note;
		my $isbn;
		if (length($lineitem->{isbn})==10 || substr($lineitem->{isbn},0,3) eq "978" || index($lineitem->{isbn},"|") !=-1)
		{
			$isbn=Rebus::EDI::cleanisbn($lineitem->{isbn});
			$isbn=Business::ISBN->new($isbn);
			if ($isbn)
			{
				if ($isbn->is_valid)
				{
					$isbn=($isbn->as_isbn13)->isbn;
				}
				else
				{
					$isbn="0";
				}
			}
			else
			{
				$isbn=0;
			}
		}
		else
		{
			$isbn=$lineitem->{isbn};
		}
		
		### line number, isbn
		$order_message.="LIN+$linecount++".$isbn.":EN'";
		$segment++;
		
		### isbn as main product identification
		$order_message.="PIA+5+".$isbn.":IB'";
		$segment++;
		
		### title
		$order_message.="IMD+L+050+:::".Rebus::EDI::string35escape(Rebus::EDI::escape_reserved($lineitem->{title}))."'";
		$segment++;
		
		### author
		$order_message.="IMD+L+009+:::".Rebus::EDI::string35escape(Rebus::EDI::escape_reserved($lineitem->{author}))."'";
		$segment++;
		
		### publisher
		$order_message.="IMD+L+109+:::".Rebus::EDI::string35escape(Rebus::EDI::escape_reserved($lineitem->{publisher}))."'";
		$segment++;
		
		### date of publication
		$order_message.="IMD+L+170+:::".Rebus::EDI::escape_reserved($lineitem->{year})."'";
		$segment++;
		
		### binding
		$order_message.="IMD+L+220+:::".Rebus::EDI::escape_reserved($lineitem->{binding})."'";
		$segment++;
		
		### quantity
		$order_message.="QTY+21:".Rebus::EDI::escape_reserved($lineitem->{quantity})."'";
		$segment++;
		
		### copies
		my $copyno=0;
		foreach my $copy (@{$lineitem->{copies}})
		{
			my $gir_cnt=0;
			$copyno++;
			$segment++;
			
			### copy number
			$order_message.="GIR+".sprintf("%03d",$copyno);
			
			### quantity
			$order_message.="+1:LQT";
			$gir_cnt++;
			
			### Library branchcode
			$order_message.="+".$copy->{llo}.":LLO";
			$gir_cnt++;
			
			### Fund code
			$order_message.="+".$copy->{lfn}.":LFN";
			$gir_cnt++;
			
			### call number
			if ($copy->{lcl})
			{
				$order_message.="+".$copy->{lcl}.":LCL";
				$gir_cnt++;
			}
			
			### copy location
			if ($copy->{lsq})
			{
				$order_message.="+".Rebus::EDI::string35escape(Rebus::EDI::escape_reserved($copy->{lsq})).":LSQ";
				$gir_cnt++;
			}
			
			### circ modifier
			if ($gir_cnt>=5)
			{
				$order_message.="'GIR+".sprintf("%03d",$copyno)."+".$copy->{lst}.":LST";
			}
			else
			{
				$order_message.="+".$copy->{lst}.":LST";
			}
			
			### close GIR segment
			$order_message.="'";
			
			$note=$copy->{note};
		}
		
		### Freetext item note
		if ($note)
		{
			$order_message.="FTX+LIN+++:::$note'";
			$segment++;
		}
		
		### price
		if ($lineitem->{price})
		{
			$order_message.="PRI+AAB:".$lineitem->{price}."'";
			$segment++;
		}
		
		### currency
		$order_message.="CUX+2:".$lineitem->{currency}.":9'";
		$segment++;
		
		### Local order number
		$order_message.="RFF+LI:".$lineitem->{rff}."'";
		$segment++;
		
		### Quote reference (if in response to quote)
		if ($order->{quote_or_order} eq 'q')
		{
			$order_message.="RFF+QLI:".$lineitem->{qli}."'";
			$segment++;
		}
	}
	### summary section header and number of lineitems contained in message
	$order_message.="UNS+S'";
	$segment++;
	
	### Number of lineitems contained in the message_count
	$order_message.="CNT+2:$linecount'";
	$segment++;
	
	### number of segments in the message (+1 to include the UNT segment itself) and reference number from UNH segment
	$segment++;
	$order_message.="UNT+$segment+".$ref."'";
	
	### Exchange reference number from UNB segment
	$order_message.="UNZ+1+".$exchange."'";	
	return $order_message;
}

sub post_process_quote_file {
	my ($self,$remote_file,$ftp_account)=@_;
	
	### connect to vendor ftp account
	my $filename=substr($remote_file,rindex($remote_file,'/')+1);
	use Net::FTP::File;
	my $ftp=Net::FTP->new($ftp_account->{host},Timeout=>10) or die "Couldn't connect";
	$ftp->login($ftp_account->{username},$ftp_account->{password}) or die "Couldn't log in";
	$ftp->cwd($ftp_account->{in_dir}) or die "Couldn't change directory";
	
	### move file to another directory
	#my $new_dir='processed';
	#my $new_file=$new_dir."/".$filename;
	#$ftp->copy($filename, $new_file) or die "Couldn't move remote file to $new_file ";
	#$ftp->delete($filename);
	#$ftp->quit;
		
	### rename file
	my $rext='.EEQ';
	my $qext='.CEQ';
	$filename=~ s/$qext/$rext/g;
	$ftp->rename($remote_file,$filename) or die "Couldn't rename remote file";
}

1;

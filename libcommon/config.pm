package libcommon::config;
use Exporter;
use utf8;
use Encode;
use strict;



if (defined $ENV{"CONFIG_FILE"}) {
  push (@libcommon::config::globalConf, $ENV{"CONFIG_FILE"});
}

our @EXPORT = qw/getKey getSectionKeys getSection load displayConfig/;

sub addToConf {
    push @libcommon::config::globalConf, shift;
}

sub getSectionsList {
	my $self = shift;
        return sort keys %{$self->{ini}};
}

sub getSectionKeys {
	my $self = shift;
	my $section = shift // $self->{"section"};
        return sort keys %{$self->{ini}->{$section}};
}

sub getSection {
	my $self = shift;
	my $section = shift // $self->{section};
	my $config = { ini => {}, section => $section };
	
	libcommon::log::printf("critical", "Pas de section $section chargée") if not grep "$section", $self->getSectionsList();
	$config->{ini}->{$section} = $self->{ini}->{$section};	

        return bless $config, __PACKAGE__;
}

sub getKey {
	my $self = shift;
	my $key  = shift // undef;
        my $info = shift//"value";
        my $section = shift // $self->{section};

        libcommon::log::printf("critical", "Missing argument key for getKey function") unless defined $key;	
        libcommon::log::printf("critical", "Missing argument section") unless defined $section;	
	libcommon::log::printf("error", "Key is not defined ($key)") if (!defined $self->{ini}->{$section}->{$key});
	return $self->{ini}->{$section}->{$key}->{$info};
}

sub getKeyPath {
	my $self = shift;
	my $key  = shift // undef;
        my $info = shift//"value";
        my $section = shift // $self->{section};
        
        libcommon::log::printf("critical", "Missing argument key for getKeyPath function") unless defined $key;	
        libcommon::log::printf("critical", "Missing argument section for getKeyPath function") unless defined $section;	
	libcommon::log::printf("error", "Key is not defined ($key)") if (!defined $self->{ini}->{$section}->{$key});
	
        my $path = $self->getKey($key);
        if ($path !~ /\/$/ )
        {
            $path.= "/";
        }
        return $path;
}

sub setKey {
	my $self = shift;
	my $key  = shift;
	my $val  = shift;
	my $fich = shift;
        my $section = shift // $self->{section};
        #foreach my  $element ( keys %{$self->{ini}}){
        #	if ($key =~ /$element/)
        #	{
#			$self->{ini}->{$element}->{valeur}  sera ecrasé par $val dans le fichier $fich\n" );
        #		libcommon::log::printf("warning", "la cle $key existe deja dans le fichier $element->{fichier} ,$element->{valeur}  sera ecrasé par $val dans le fichier $fich ");

        #	}
        #}
	$self->{ini}->{$section}->{$key} = {value=>$val,file=>$fich}; 

}



sub load {
	# check @ARGV to see if more config should be read...
        #my $name = shift;
	@libcommon::config::globalConf = @_;
	libcommon::log::printf("debug", "Starting config loading \@ %s", join(", ", @libcommon::config::globalConf));
	my $config = libcommon::config->new(@libcommon::config::globalConf);
	libcommon::log::printf("debug", "Success config loading");
	return  $config;
}


sub new {
	my $class = shift;
	my @configFiles = @_;
	my $config = {};
	my ($line, $section ,$key, $val);
        $section = "UNDEFINED";
	libcommon::log::dumper("notice",@configFiles);
	foreach my $file (@configFiles) {
                if (! -f $file) {
			libcommon::log::printf("critical", "config file %s does not exists", $file) ;
			next;
                }
		open (CONFIGFILE , "<:encoding(UTF-8)" , $file ) or  die "can't open $file";
		while($line = <CONFIGFILE>){
                        next if $line =~ /^#/;
			if ($line  =~ /^\[([\w=]+)\]/) {
				$section = $1;
                                if (not exists $config->{$section}) {
                                   $config->{$section} = {};
                                }
			} elsif ($line =~ /([\w\-\.]+)\s*=\s*(.+)?$/) {
				($key, $val) = ($1, $2);
				if ( $key =~/include/) {
					$val =~ s/\[//;
					$val =~ s/\]//;
					libcommon::log::printf("notice", "Including files");
					foreach my $f (split (/,/, $val)) {
						libcommon::log::printf("notice", "  - %s", $f);
						push @configFiles, $f;
					}
				} else {
					$config->{$section}->{$key} = { 
						"value"   => $val, 
						"file"    => $file
					};
				}
			}
		}
		close (CONFIGFILE);
		libcommon::log::printf("notice", "Success including config file %s", $file);
	}

	# ouvrir les fichiers, les lire, pousser les clefs / valeur. 
	# print warning si la clef est "surchargée" (de quel fichier a quel fichier).
	# pousse dans la config

	return bless {
		ini =>  $config
	}, $class;
}


# log the complete configuration
sub displayConfig {
    my $self = shift;
    my $logLevel = shift // "notice";

    my $section = shift;
    if ($section)
    {
            libcommon::log::printf($logLevel, "Section %s",  $section);
        foreach my $k ($self->getSectionKeys($section)) {
            libcommon::log::printf($logLevel, "  %-30s = %s", $k, $self->getKey($k, undef, $section));
        }
    }
    else
    {
        foreach $section ($self->getSectionsList()) {
            libcommon::log::printf("notice", "[%s]", $section);
            foreach my $k ($self->getSectionKeys($section)) {
                libcommon::log::printf($logLevel, "  %-30s = %s", $k, $self->getKey($k, undef, $section));
            }
        }
    }
}
sub TO_JSON { return { %{ shift() } }; }

1;


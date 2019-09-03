# package destiné à formatter les messages de log par niveau alert / warning / notice / debug / error / critical

package libcommon::log;
use IO::Dir;
use Carp qw(longmess);
use Exporter;
use POSIX qw/strftime/;
use Data::Dumper qw/Dumper/;
use Try::Tiny;
use File::Path;
use Archive::Tar;
use YAML;
use strict;
use utf8;
use constant TEE => '| tee ';

our @EXPORT_OK = qw /printf compress reset flush/;

sub init {

	$libcommon::log::DEBUG = "debug";
	$libcommon::log::NOTICE = "notice";
	$libcommon::log::WARNING = "warning";
	$libcommon::log::ERROR = "error";
	$libcommon::log::CRITICAL = "critical";
	$libcommon::log::JOURNAL = "journal";

	$libcommon::log::DepthMax = 0;
	$libcommon::log::indentStep = " ";
        $libcommon::log::jnl = "";
    
	my $log = *STDOUT;
        binmode($log, ":utf8");
	if ($libcommon::log::config == undef )
	{
		$libcommon::log::traceLevel = $ENV{LOGTRACE} // "notice";
		$libcommon::log::dieLevel = 'error';
		$libcommon::log::logHandler = $log;
		$libcommon::log::logTemplate= '[%l][%d][%p]';
		$libcommon::log::messagePosition='AFTER';
                $libcommon::log::activeTemplate= 1;
	}
       
	$| = 1;
}

sub initSentry
{
    use Sentry::Raven;
    use Devel::StackTrace;
    use libcommon::raven;
    use DB;
    my $config = shift;
    $libcommon::log::raven = libcommon::raven->new($libcommon::log::confRaven);
}
sub addConfig
{
	$libcommon::log::config = shift;
}

sub reset {
	print "\n\r";
}
sub mojoLog {
    $libcommon::log::InstName = shift;
    require Mojo::Log;
    my $config = $libcommon::log::config->getSection("LOG");
    my $mojoConfig = $libcommon::log::config->getSection("MOJOLICIOUS");
    my $log = Mojo::Log->new(path => $config->getKeyPath('logRepository'). $libcommon::log::InstName . "/". 
      strftime($config->getKey('logDirTemplate'), localtime).".ServerWeb.log", level=>"info"); 
    return $log;
}

sub isDaemon {
    $libcommon::log::PID = shift;
    $libcommon::log::InstName = shift;
    $libcommon::log::jnl = shift;
    my $config = $libcommon::log::config->getSection("LOG");
    mkpath($config->getKeyPath('logRepository').$libcommon::log::InstName);
    $libcommon::log::logFile =  $config->getKeyPath('logRepository'). $libcommon::log::InstName . "/". 
      strftime($config->getKey('logDirTemplate'), localtime).".Daemon.log"; 
    open (my $log, ">>" ,$libcommon::log::logFile)
        or die("can't open logFile $libcommon::log::logFile $!");
    $libcommon::log::logHandler = $log;
    binmode($libcommon::log::logHandler,':utf8');
    $libcommon::log::isConfLoaded = "OK";
    $libcommon::log::deamon =1;
}

sub confLoad {
    my $pack = shift;
    my $config = shift;
    $libcommon::log::config = $config->getSection("LOG");
    if ($libcommon::log::config->getKey("sentry_on") == 1)
    {
        $libcommon::log::confRaven = $config->getSection("SENTRY");
        initSentry();
    }
    $config = $config->getSection("LOG");
    $libcommon::log::logDir =  $libcommon::log::config->getKeyPath('logRepository') . "local/". 
    strftime($libcommon::log::config->getKey('logDirTemplate'), localtime); 
    $libcommon::log::logFile =  $libcommon::log::config->getKeyPath('logRepository') . "local/".
    strftime($config->getKey('logDirTemplate') . "/" . 
        $libcommon::log::config->getKey('logFileTemplate'), localtime) . ".log";
    mkpath($libcommon::log::logDir);
    mkpath($config->getKeyPath('logRepository') . "local/archive");
    $libcommon::log::traceLevel = $config->getKey('trace');
    $libcommon::log::dieLevel = $config->getKey('die');
    open my $log, ">>", $libcommon::log::logFile;
    binmode($log,':utf8');
    $libcommon::log::logHandler = $log;
    $libcommon::log::isConfLoaded = "OK";
    $libcommon::log::logTemplate= $config->getKey('logTemplate');
    $libcommon::log::messagePosition=$config->getKey('logMessagePosition');
    $libcommon::log::activeTemplate=$config->getKey('logActiveTemplate');
    libcommon::log::compress();
}


sub compress {
 	my $config=$libcommon::log::config->getSection("LOG");
        my $tar = Archive::Tar->new;
	my $replog = $config->getKeyPath('logRepository')."local/";
	opendir(my $dh, $replog) || "can't opendir";
	while(readdir $dh){
		if ( -d "$replog/$_" && ("$replog$_" ne $libcommon::log::logDir)==1 && $_ !~/^\./ && $_ ne "archive" && $_ != ""){
			my $dscourant= $_;
                        $tar->add_files(<$replog$_/*>);
                        $tar->write("$replog/archive/$_.tgz", "COMPRESS_GZIP");
                        $tar->clear();
                        unlink(<$replog$_/*>) or die "$! : $replog / $_ ";
                        rmdir "$replog"."$_" or die "cant remove $!";
		}
	}
}

sub rotateDaemon
{
    if($libcommon::log::InstName && $libcommon::log::deamon == 1)
    {
    close($libcommon::log::logHandler);
    my $config = $libcommon::log::config->getSection("LOG");
    
    $libcommon::log::logFile =  $config->getKeyPath('logRepository') . $libcommon::log::InstName . "/".
    strftime($config->getKey('logDirTemplate'), localtime).".Daemon.log"; 
    $libcommon::log::logDir = undef; 
    open my $log, ">>" , $libcommon::log::logFile
        or die("can't open logFile $libcommon::log::logFile $!");
    
    $libcommon::log::logHandler = $log;
    binmode($libcommon::log::logHandler,':utf8');
    }
}




sub numTraceLevel {
	my $tl = lc shift;
	return   $tl eq "debug" ? 1 : 
		$tl eq "notice" ? 2 : 
                $tl eq "journal" ? 3 :
		$tl eq "warning" ? 4 : 
		$tl eq "error" ? 5 : 
		$tl eq "critical" ? 6 : $tl ;
}

sub dumper {
	my ($level,@parms) = @_;
	my $Cl = uc(substr($level,0,1));
	my $time = strftime("%Y/%m/%d %H:%M:%S",localtime);
	my ($package, $filename, $line)= caller(1);
	my $chaine2;
	if (numTraceLevel($level) >= numTraceLevel($libcommon::log::traceLevel))
	{
		$chaine2 = Template($chaine2, $level, $Cl , $time, $package, $filename, $line);
#    printf $libcommon::log::logHandler "[%s][%s][%-25s] %s\n",$Cl, $time, $package."::".$line, "-" x 30;
#    printf STDOUT "[%s][%s][%-25s] %s\n",$Cl, $time, $package."::".$line, "-" x 30;
		$chaine2 .= "-" x 30;
		printf $libcommon::log::logHandler "$chaine2 \n"; 
		if ($libcommon::log::logHandler != *STDOUT)
		{
		printf STDOUT "$chaine2 \n";
		}
		flush();
		foreach my $param (@parms) {
			my $var = Dump($param);
			utf8::decode($var);
			print $libcommon::log::logHandler $var;
			if ($libcommon::log::logHandler != *STDOUT)
			{
				print $var;
			}
		}
		printf $libcommon::log::logHandler "$chaine2 \n"; 
			
		if ($libcommon::log::logHandler != *STDOUT)
		{
			printf STDOUT "$chaine2 \n";
		}
	}

#    printf $libcommon::log::logHandler "[%s][%s][%-25s] %s\n",$Cl, $time, $package."::".$line, "-" x 30;
#    printf STDOUT "[%s][%s][%-25s] %s\n",$Cl, $time, $package."::".$line, "-" x 30;
	flush();


}
sub printf {
	my ($level, $message, @parms) = @_;
	my $logConfig;
	#if ($libcommon::log::config != undef && !$libcommon::log::isConfLoaded)
	#{         
	#	 $logConfig = $libcommon::log::config->getSection("LOG");
	#	if ($logConfig == undef) {
	#		traceAndDie("critical", "No LOG configuration could be loaded");
	#      }
	#	confLoad($logConfig);
	#}
	
	grep { $_ eq $level } ( 
			$libcommon::log::DEBUG, 
			$libcommon::log::NOTICE,
			$libcommon::log::WARNING,
			$libcommon::log::ERROR,
			$libcommon::log::CRITICAL,
			$libcommon::log::JOURNAL
			) or die "log::printf call without valid trace level ! \n". Dump(longmess());
	if (numTraceLevel($level) >= numTraceLevel($libcommon::log::dieLevel))
	{
		traceAndDie($level, $message, @parms);
	}
	else
	{
		#Template($level, $message, @parms);
		trace($level, $message, @parms);
	}
}






   


sub Template{
	my ($chaine2,$level,$Cl,$time,$package,$filename,$line)=  @_;
#recuperer le template
	my $template=$libcommon::log::logTemplate;
	my @templates=@_;


	foreach my $v (split (/\s/,$template)){
		push @templates,$v;
	} 
	my $chaine ;
	my  $chaine1;

	foreach my $var (@templates)
	{
# print $var;
		if ($var=~/\[(%l)\]/){

			$chaine .="[%s]";
			$chaine1 .= $Cl.", ";
 $chaine2 .= "[$Cl]";
		}
		if ($var=~/\[(time)\]/){

			$chaine .="[%s]";
			$chaine1 .=  $time.", ";
$chaine2 .= "[$time]";

		}
		if ($var=~/\[(%p::%c)\]/){

			$chaine .="[%s-25s]";
			$chaine1 .=  $package."::".$line.",";
			$chaine2 .= "[$package"."::"."$line]";
		}

	}
#	$chaine .= " %s%s\n";
	#$chaine1 .=  $indent." ,".$str ;
#	$chaine2 .=  $indent.$str;
#	if (numTraceLevel($level) >= numTraceLevel($libcommon::log::traceLevel)) {
#	binmode($libcommon::log::logHandler, ":utf8");
#printf $libcommon::log::logHandler "$chaine".",". $chaine1;
#printf STDOUT "$chaine ,". $chaine1;
#	printf $libcommon::log::logHandler "$chaine2";
#	print STDOUT "$chaine2";
#
#}
#
return $chaine2;
}


sub trace {
	my ($level, $message, @parms) = @_;
	my $Cl = uc(substr($level,0,1));
	my $time = strftime("%Y/%m/%d %H:%M:%S",localtime);
	my ($package, $filename, $line)= caller(1);
	my $indent = indent(); 
	my $str = message($message,@parms);
	my $chaine2;
#	my $chaine2= messagePosition($level,$Cl ,$time, $package, $filename, $line, $str,$indent);
#	my $verif = disableTemplate();
#print " $verif \n";
	if ( $libcommon::log::activeTemplate != 0){
	 $chaine2 = messagePosition($level,$Cl ,$time, $package, $filename, $line, $str,$indent);
        }
	else 
	{
        $chaine2 = $str;
	}
	$chaine2 .= " \n";
		if (numTraceLevel($level) >= numTraceLevel($libcommon::log::traceLevel)) {
		binmode($libcommon::log::logHandler, ":utf8");
		printf $libcommon::log::logHandler "$chaine2 ";
                if ($level eq "journal")
                {
                    if ($libcommon::log::jnl)
                    {
                        $libcommon::log::jnl->print($chaine2);
                    }
                }
		if ($libcommon::log::logHandler != *STDOUT)
		{
			print STDOUT "$chaine2 ";
		}
		}	
}
sub messagePosition{
	my ($level,$Cl ,$time, $package, $filename, $line,$str,$indent)=@_;
	my $chaine2;
	my $position = $libcommon::log::messagePosition;
	if ($position eq "BEFORE"){
	$chaine2 = $str.$indent;
        $chaine2 = Template($chaine2, $level, $Cl , $time, $package, $filename, $line);
		return $chaine2;
	}	
	if ($position eq "AFTER"){
 	$chaine2 =Template($chaine2, $level, $Cl , $time, $package, $filename, $line);
	   $chaine2 .=  $indent.$str;
	}

}
sub traceAndDie {
	my ($level, $message, @parms) = @_;
	trace($level, $message, @parms);
        $level =~ s/critical/fatal/;
        $libcommon::log::raven->sendMessage2Sentry($level,message($message,@parms)) if $libcommon::log::raven;
        if ($libcommon::log::deamon == 1 && numTraceLevel($level) == 5)
        {
            kill USR1 => $libcommon::log::PID;
        }
	#else
	# {
		#die sprintf("$message", @parms)."\n";
		#}
}

sub flush {
	my $old = select($libcommon::log::logHandler);
	$| = 1;
	select $old;
	if ($libcommon::log::config)
	{
	my $config = $libcommon::log::config->getSection("LOG");

	if ($libcommon::log::logFile ne $config->getKeyPath('logRepository').$libcommon::log::InstName."/".strftime($config->getKey('logDirTemplate'), localtime).".Daemon.log")
	{
		libcommon::log::rotateDaemon();
	}
}
}

#########A verif
sub indent {
	my $depth = 0;
	while (my @frame = caller $depth) {
		$depth++;
	}
	$libcommon::log::DepthMax = $depth if ($depth > $libcommon::log::DepthMax);
	my $decal = $libcommon::log::DepthMax - $depth;
	return ($libcommon::log::indentStep x $decal);
}

sub message {
	my $message  = shift;
	my @parms = @_;
	return sprintf($message, @parms);
}


sub DESTROY {
	my $self = shift;
	libcommon::log::printf("debug", "We are going to close the log Handler");
	close($libcommon::log::logHandler);
}

1;


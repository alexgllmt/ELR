package libcommon::raven;
use Sentry::Raven;
use Devel::StackTrace;
use DB;
use libcommon::log;
use libcommon::config;
use Data::Dumper qw/Dumper/;
use parent Sentry::Raven;
sub new
{
    my $class =shift;
    my $config = shift;
    my $dsn = $config->getKey("sentry_dsn");
    my $logger = $config->getKey("logger");
    my $environnement = $config->getKey("environnement");
    my $release = $config->getKey("release");
    my $server_name = $config->getKey("server_name");
    my $raven = Sentry::Raven->new( sentry_dsn => $dsn, logger => $logger, platform => 'perl', server_name => $server_name, environment => $environnement, release => $release, list_max_length => 50);
    return bless $raven,$class;
}

sub sendMessage2Sentry
{
    my $self = shift;
    my $level = shift;
    my $message = shift;
    my $frames = generateFrame();
    $self->merge_extra(Path => \@INC, , Environment => \%ENV);
    $self->merge_modules(%INC);
    print Dumper $self->get_context();
    #$self->merge_tags(titi => "silvestre");
    # $self->capture_stacktrace($trace,level => $level, Sentry::Raven->exception_context($message, type=>$level));
    $self->capture_message($message,Sentry::Raven->stacktrace_context($frames), Sentry::Raven->exception_context($level, type=>"Libcommon $level"),level=>$level);
}

sub generateFrame
{
    my $frames =[];
    my $i = 3;
    my $prev ="";
    while (  my @call_details = do { 
             package DB; #cf https://metacpan.org/release/Devel-StackTrace/source/lib/Devel/StackTrace.pm
             @DB::args = ();
             caller($i++);
             }
     ){
            my $j = 1;
            my @array =  map { $_ } @DB::args;
            my $line_prev = [];
            my $line_post = [];
            my $context_line = "";
            open (my $file, '<', $call_details[1]); #or die $!;

            while (<$file>)
            {
                if ($. >= ($call_details[2] - 3) && $. < $call_details[2] )
                {
                    push @{$line_prev}, $_;
                    next;
                }
                if ($. <= ($call_details[2] + 3) && $. > $call_details[2])
                {
                    push @{$line_post}, $_;
                    next;
                }
                if ($. == $call_details[2] )
                {
                    $context_line = $_;
                    next;
                }
            }
            close $file;
            my $filename = $call_details[1];
            $prev = (caller($i))[3] || "main";
            if ($call_details[1] eq '-e'){
                $filename="embedded";
                $context_line = "perl -e".$call_details[3];
                $prev = "main";
                @array = @ARGV;
            }
            push @{$frames}, {filename => $filename,
                function => $prev,
                module   => $call_details[0],
                lineno   => int($call_details[2]),
                context_line => $context_line,
                post_context => $line_post,
                pre_context => $line_prev,
                vars => {args => \@array}
            };
            # }
            $prev = $call_details[3];
    }
    return $frames;
}
1;

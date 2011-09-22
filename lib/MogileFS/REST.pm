package MogileFS::REST;
use Dancer ':syntax';
use Carp;
use HTTP::Status ':constants';
use MogileFS::Client;
use Data::Dumper;

our $VERSION = '0.2';

my $mogservers;
if (my $cnf = $ENV{MOGILEFS_REST_SERVERS}) {
    $mogservers = [  split /,/, $cnf ];
}
$mogservers ||= config->{servers};
my $default_mogclass = $ENV{MOGILEFS_REST_DEFAULT_CLASS} || "normal";

sub get_client {
    my ($domain) = @_;
    my $client = MogileFS::Client->new(
        domain => $domain,
        hosts  => $mogservers,
    );
    return $client;
}

debug("Mogile config: " . (Dumper [$mogservers]));

get '/' => sub {
    header('Content-Type' => 'text/plain');
    return <<EOA
This is a simple REST API abstraction to MogileFS, so that
we can store and retrieve files from mogile, without having to reimplement
a MogileFS client in different languages.

Files are hosted at:
/:domain/:key

you can HEAD/GET/PUT/DELETE on that endpoint, please README for more details.

EOA

};

get '/:domain/:key' => sub {
    my $domain = param('domain');
    my $key = param('key');
    my $req = request;
    my $can_reproxy = 0;
    my $capabilities = $req->header('X-Proxy-Capabilities');
    if ($capabilities && $capabilities =~ m{\breproxy-file\b}i) {
        $can_reproxy = 1;
    }
    my $mogile_key = $key;
    my $client = get_client($domain);
    my @paths = $client->get_paths($mogile_key, { no_verify => 1 });
    return _not_found() unless @paths;
    header('X-Reproxy-URL' => join " ", @paths);
    if ($can_reproxy) {
        status(HTTP_NO_CONTENT);
        return '';
    }
    else {
        status(HTTP_OK);
        header('Content-Type' => 'application/octet-stream');
        ## should we do another request to get x-reproxy-expected-size
        if ($req->is_head) {
            debug("request is HEAD, returning no content");
            header('Content-Length', 0);
            return '';
        }
        my $dataref = $client->get_file_data($mogile_key);
        return $$dataref;
    }
};

del '/:domain/:key' => sub {
    my $domain = param('domain');
    my $key = param('key');
    my $mogile_key = $key;
    my $req = request;

    my $client = get_client($domain);
    my $rv = $client->delete($mogile_key);
    my $e = $client->errstr;
    return _error("Couldn't delete $domain/$mogile_key: $e") unless $rv;
    status(HTTP_NO_CONTENT);
    return '';
};

put '/:domain/:key' => sub {
    my $domain = param('domain');
    my $key = param('key');
    my $mogile_key = $key;

    my $req = request;
    my $mogclass = $req->header('X-MogileFS-Class') || $default_mogclass;
    my $dataref = \request->body;

    my $size;
    {
        use bytes;
        $size = bytes::length($$dataref);
    }
    my $opts = { bytes => $size };
    my $client = get_client($domain);
    my $rv = $client->store_content($mogile_key, $mogclass, $dataref, $opts);
    if ($rv) {
        status(HTTP_CREATED);
        return '';
    }
    else {
        my $errstr = $client->errstr;
        error("Error is $errstr");
        return _error("Couldn't save this key: $errstr");
    }
};

sub _not_found {
    status(HTTP_NOT_FOUND);
    return "Not such file";
}

sub _error {
    header('Content-Type' => 'text/plain');
    status(HTTP_INTERNAL_SERVER_ERROR);
    return $_[0] || "Server Error"
}

true;

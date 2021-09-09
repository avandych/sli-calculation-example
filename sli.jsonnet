local rule(name, expr, ruleLabels) = {
  record: name,
  expr: expr,
  labels: ruleLabels,
};

local sliLess(expr, threshold, name) =
rule(
    'service:sli:conformity:status',
    std.format('%s < bool %f', [expr, threshold]),
    {
        name: name
    }
);

local sliGreater(expr, threshold, name) =
rule(
    'service:sli:conformity:status',
    std.format('%s > bool %f', [expr, threshold]),
    {
        name: name
    }
);


local sliClean(name) = rule(
    std.format('service:sli:clean:%s', [name]),
    std.format('service:sli:%s{namespace=~".+", service=~".+", name=~".+"} >= 0', [name]),
    {},
);

local latencyRule(serviceName, endpoint, quantile, name) = 
local expr = std.format('histogram_quantile(%s, sum by (namespace, service, le) (rate(service_http_request_endpoint_bucket{service="%s", route="%s"}[%s])))', [quantile, serviceName, endpoint, '5m']);
rule(
    std.format('service:sli:%s', [name]),
    expr,
    {
        name: name
    }
);

local latencySli(serviceName, endpoint, quantile, threshold) = 
local name = std.format('latency:%s:%s:%s:ms', [std.asciiLower(std.reverse(std.split(endpoint, '/'))[0]), std.split(quantile, '.')[1], threshold]);
[
    latencyRule(serviceName, endpoint, quantile, name),
    sliClean(name),
    sliLess(std.format('service:sli:clean:%s', [name]), threshold, name)
];


local healthRule(serviceName, name) = 
local expr = std.format('min by(namespace, service) (service_health{service=~"%s", status="healthy"})', [serviceName]);
rule(
    std.format('service:sli:%s', [name]),
    expr,
    {
        name: name
    }
);

local healthSli(serviceName) = 
local name = 'health';
[
    healthRule(serviceName, name),
    sliClean(name),
    sliGreater(std.format('service:sli:clean:%s', [name]), 0, name)
];


local sliConformityAvg(serviceName, window) = rule(
    std.format('service:sli:conformity:avg%s', [window]),
    std.format('avg_over_time(service:sli:conformity:status[%s]) * 100', [window]),
    {},
);

local sliConformity(serviceName) = 
[
    sliConformityAvg(serviceName, '1h'),
    sliConformityAvg(serviceName, '1d'),
    sliConformityAvg(serviceName, '1w'),
    sliConformityAvg(serviceName, '4w')
];

local serviceName = 'my-service';

{
    groups: [{
        name: serviceName + '.rules',
        rules: sliConformity(serviceName) + latencySli(serviceName, '/API/MYENDPOINT', '0.95', 100) + healthSli(serviceName)
    }],
}
.pragma library
.import "Utils.js" as Utils

function apply(items, rules, categoriesById) {
    var enabledRules = Utils.asArray(rules).filter(function(rule) {
        return rule && rule.enabled !== false && Utils.asArray(rule.terms).length > 0;
    });

    return Utils.asArray(items).map(function(item) {
        return applyToItem(item, enabledRules, categoriesById || {});
    });
}

function applyToItem(item, rules, categoriesById) {
    var output = Utils.deepCopy(item);
    var includeRulesInScope = [];

    output.matchedRuleIds = [];
    output.matchedTerms = [];
    output.excluded = false;
    output.highlighted = false;

    for (var i = 0; i < rules.length; i++) {
        var includeRule = rules[i];

        if (includeRule.mode === "include" && ruleScopeMatches(includeRule, output)) {
            includeRulesInScope.push(includeRule);
        }
    }

    if (includeRulesInScope.length > 0) {
        var anyIncludeMatched = false;

        for (var inc = 0; inc < includeRulesInScope.length; inc++) {
            if (ruleTermsMatch(includeRulesInScope[inc], output, categoriesById)) {
                anyIncludeMatched = true;
                Utils.uniquePush(output.matchedRuleIds, includeRulesInScope[inc].id);
                appendMatchedTerms(output, includeRulesInScope[inc]);
            }
        }

        if (!anyIncludeMatched) {
            output.excluded = true;
        }
    }

    for (var r = 0; r < rules.length; r++) {
        var rule = rules[r];

        if (!ruleScopeMatches(rule, output) || !ruleTermsMatch(rule, output, categoriesById)) {
            continue;
        }

        Utils.uniquePush(output.matchedRuleIds, rule.id);
        appendMatchedTerms(output, rule);

        if (rule.mode === "exclude") {
            output.excluded = true;
        } else if (rule.mode === "highlight") {
            output.highlighted = true;
        }
    }

    return output;
}

function ruleScopeMatches(rule, item) {
    var feedIds = Utils.asArray(rule.feedIds);
    var categoryIds = Utils.asArray(rule.categoryIds);

    if (feedIds.length > 0 && feedIds.indexOf(item.feedId) === -1) {
        return false;
    }
    if (categoryIds.length > 0 && categoryIds.indexOf(item.categoryId) === -1) {
        return false;
    }

    return true;
}

function ruleTermsMatch(rule, item, categoriesById) {
    var terms = Utils.asArray(rule.terms);
    var category = categoriesById[item.categoryId] || {};
    var haystack = [
        item.title,
        item.summary,
        item.author,
        item.feedName,
        category.name
    ].join(" ");

    for (var i = 0; i < terms.length; i++) {
        if (Utils.containsTerm(haystack, terms[i])) {
            return true;
        }
    }

    return false;
}

function appendMatchedTerms(item, rule) {
    var terms = Utils.asArray(rule.terms);

    for (var i = 0; i < terms.length; i++) {
        Utils.uniquePush(item.matchedTerms, terms[i]);
    }
}

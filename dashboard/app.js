/* app.js - Interactive dissertation dashboard
 * Multi-page tab system: each nav tab shows one section at a time.
 * Chart sections (Sample, Effects) render lazily on first tab activation.
 * Data: dashboard/data/dashboard.json (static, frozen 2026-06-12)
 * Dependencies: Chart.js 4 (CDN)
 */

'use strict';

// Module-scope references so theme refresh can redraw charts without re-fetching
var _dashData            = null;
var renderDemoChartGlobal = null;

// ---------------------------------------------------------------------------
// Explain-it panel: plain-language explanations per section, three audience
// levels. Content is written for: a curious non-specialist (Curious Mind),
// an organizational decision-maker (Business Impact), and a researcher or
// methodologist (Deep Dive).
// ---------------------------------------------------------------------------

var _explainCurrentSection = 's-study';

var EXPLANATIONS = {
    's-about': {
        curious:
            'This dashboard was built by the same person who ran the study: a PhD candidate in ' +
            'Industrial-Organizational psychology who also happens to write the code that turns ' +
            'raw survey data into pages like this one. Nothing on this site required an outside ' +
            'design team or a data-visualization contractor. ' +
            'The "About" tab is just a quick way to see who is behind the numbers and where to ' +
            'find more of his work.',
        business:
            'The researcher combines a psychology PhD with hands-on data engineering and machine ' +
            'learning experience across consulting, banking, and retail. That dual background is ' +
            'why this dashboard exists at all: most academic findings never leave a PDF, but a ' +
            'background in production data systems makes it possible to ship results as an ' +
            'interactive product instead.',
        expert:
            'Methodologically, the overlap between psychometric training (measurement invariance, ' +
            'multilevel modeling, CFA) and applied data engineering (ETL/ELT pipelines, cloud ' +
            'infrastructure, MLOps) is what enabled a from-scratch build script and static site ' +
            'rather than a third-party BI tool: the entire pipeline from raw CSV exports to this ' +
            'page is version-controlled and reproducible.'
    },
    's-study': {
        curious:
            'Most burnout research asks employees once a year how they are doing. ' +
            'That is like asking how a workout felt after you have already showered and ' +
            'forgotten the effort. This study asked three times in one workday: does the ' +
            'tiredness and frustration building up in real time actually push someone toward ' +
            'thoughts of quitting on that same day? ' +
            'The answer is yes. Your workday is not just hours of neutral time; it actively ' +
            'shapes whether you are mentally checking out, hour by hour.',
        business:
            'Annual engagement surveys capture turnover risk in retrospect, after the feeling ' +
            'has already settled in. This study shows that depletion signals move within a ' +
            'single shift, meaning the information is there long before any survey captures it. ' +
            'Physical fatigue, emotional exhaustion, and blocked competence predicted same-shift ' +
            'withdrawal thinking, net of everything stable about the employee. ' +
            'This points toward intraday indicators as a complement to periodic surveys, not a ' +
            'replacement for them.',
        expert:
            'The study applies a three-wave ESM design within a two-level MLM framework to ' +
            'partition within-person (L1) and between-person (L2) variance in momentary turnover ' +
            'intentions. Conservation of resources theory and self-determination theory\'s need ' +
            'frustration pathways are treated as competing and complementary L1 predictors. ' +
            'Person-mean centering at L1 removes between-person confounding, ensuring that ' +
            'within-person effects cannot be artifacts of stable individual differences or ' +
            'sample composition.'
    },
    's-sample': {
        curious:
            '336 people across the United States took three short surveys on one of their work ' +
            'days. Most held at least a college degree and worked at a computer, often from home. ' +
            'They represent the kind of worker most common in today\'s economy. ' +
            'The study is upfront that factory workers and retail employees are a different story; ' +
            'what is true for an office professional may not hold for someone on a warehouse floor.',
        business:
            'The sample is 336 employed U.S. adults, primarily knowledge workers: 72% hold a ' +
            'bachelor\'s degree or higher and 57% were working remotely on their study day. ' +
            'About 76% were recruited through a vetted online panel and 24% through professional ' +
            'networks, with recruitment source controlled statistically in all models. ' +
            'This profile closely mirrors the white-collar and hybrid workforce that most HR ' +
            'leaders manage today.',
        expert:
            'Dual-source recruitment (CloudResearch N=255, snowball N=81) introduces potential ' +
            'heterogeneity handled via a dummy-coded L2 covariate in all primary models. ' +
            'Demographic composition (72% bachelor\'s+, 57% remote, 71% White) constrains ' +
            'external validity to knowledge-intensive occupations. ' +
            'ESM compliance required full three-occasion participation; 15 of 351 completers ' +
            '(4.3%) were excluded via a multi-criterion careless-response filter requiring ' +
            'flagging by at least two of three indicators: instructed response, LongString, ' +
            'and Mahalanobis distance.'
    },
    's-cofluct': {
        curious:
            'Two things co-fluctuate when they tend to go up and down together. ' +
            'This page shows that inside each person, the occasions when they feel more ' +
            'physically drained or emotionally spent are also the occasions when they think ' +
            'more about quitting, even if they are generally happy at their job. ' +
            'The burnout-turnover link is not just about being a burned-out type of person; ' +
            'it is also about whether this particular moment in the day is a depleted one.',
        business:
            'The correlations reveal what surveys miss: the same person who is content on Monday ' +
            'morning can have elevated turnover thinking by midday if their depletion spikes. ' +
            'The within-person signals for physical fatigue, emotional exhaustion, and competence ' +
            'frustration are the ones that move with withdrawal thinking in real time. ' +
            'Between persons, the pattern is even stronger, meaning chronic depletion is the ' +
            'bigger risk factor overall, but the within-day signal adds something beyond it.',
        expert:
            'The within-person matrix uses rm-correlation (Bakdash and Marusich, 2017), which ' +
            'partitions within-person covariation by treating participant ID as a nuisance factor, ' +
            'yielding correlations interpretable as average within-person associations across ' +
            'occasions. The between-person matrix uses Pearson r on person-mean aggregates. ' +
            'Comparing the two matrices reveals uniformly stronger between-person associations, ' +
            'consistent with between-person variance dominating the total pool (ICC = .79), and ' +
            'confirms that the burnout-withdrawal correlation is not solely a stable trait effect.'
    },
    's-variance': {
        curious:
            'Imagine everyone gets a score from 1 to 5 for "thinking about quitting right now" ' +
            'three times a day. If you tried to explain all the differences in those scores, 79% ' +
            'of the explanation comes from who the person is: their job situation, their history, ' +
            'their chronic burnout level. Only 21% comes from what was happening that specific hour. ' +
            'That 21% sounds small, but it is real, it is consistent, and it is the part an ' +
            'organization can actually influence before someone has already decided to leave.',
        business:
            'The headline is ICC = .79: 79% of variation in momentary turnover thinking is stable ' +
            'between persons. Chronic conditions, job quality, and individual disposition are the ' +
            'dominant factors. But the within-day 21% is the window for timely intervention. ' +
            'Unlike the stable majority, which requires addressing underlying job quality and ' +
            'satisfaction, the within-day component responds to same-day events. ' +
            'Both layers matter; they require different types of action at different timescales.',
        expert:
            'ICC(TI) = .792 is at the high end for ESM outcomes, indicating that momentary ' +
            'turnover intentions are strongly dispositionally anchored. Between-person dominance ' +
            'creates a structural constraint on L1 effect detection: within-person effects are ' +
            'estimated against a residual capped at roughly 21% of total variance. ' +
            'This contextualizes observed pseudo-d values and partially explains why within-person ' +
            'effects are smaller in absolute magnitude than between-person effects while remaining ' +
            'theoretically and practically meaningful within their level-specific variance pool.'
    },
    's-measurement': {
        curious:
            'Before trusting any results, the measuring tools themselves have to be checked. ' +
            'This page shows that the survey questions did capture what they were supposed to, ' +
            'that the factor structure held across all three check-ins, and that people were ' +
            'not just agreeing with everything. ' +
            'One specific test used an entirely unrelated question (attitude toward the color ' +
            'blue, seriously) as a control. It had near-zero correlations with all study ' +
            'variables, which rules out the possibility that the results reflect response style ' +
            'rather than real relationships.',
        business:
            'This is the quality control section. Three things were verified: the survey ' +
            'constructs measured what they claimed (factor structure confirmed), factor loadings ' +
            'were consistent across the three measurement occasions (metric invariance, so ' +
            'within-person comparisons are fair), and a statistical test ruled out common method ' +
            'bias. The correlations in the data reflect real relationships between burnout, need ' +
            'frustration, and turnover thinking, not just survey response artifacts.',
        expert:
            'Measurement validation covered: L1 MCFA (7-factor: SMBM-3f, PNTS-3f, ATCB) with ' +
            'acceptable fit; L2 CFA confirming between-person factor structure; the marker ' +
            'variable technique (Miller et al., 2024) using ATCB with all L1 rmcorr associations ' +
            '|r| < .06, ruling out systematic CMV at L1; LRT comparison of method-factor vs. ' +
            'baseline model (p = 1.00); and metric invariance across waves (delta chi-sq = ' +
            '-2.348, df = 22, p = 1.00), licensing within- and between-person predictors from ' +
            'shared item blocks.'
    },
    's-models': {
        curious:
            'Think of the models as building an explanation layer by layer, like sharpening a ' +
            'blurry photograph one adjustment at a time. Model 0 simply acknowledges that people ' +
            'differ. Each model adds more pieces: first the within-day burnout and frustration, ' +
            'then stable personality and attitude factors, then both together. ' +
            'By the end you can see exactly which pieces predict thoughts of quitting once ' +
            'everything else is held constant.',
        business:
            'The model sequence shows where the explanation of turnover thinking actually lives. ' +
            'The biggest jumps in explanatory power come when chronic job attitudes (job ' +
            'satisfaction, burnout averages) enter the model and when within-day depletion states ' +
            'are included. Each layer contributes independently. ' +
            'For practitioners: both chronic conditions and day-to-day experience predict turnover ' +
            'risk, and each requires a different lever to address.',
        expert:
            'The model sequence follows a standard incremental MLM building strategy: M0 ' +
            '(unconditional, ICC estimation) through M7b (full fixed effects). Deviance-based ' +
            'LRT and Nakagawa-Schielzeth R2 marginal/conditional decompose incremental fit at ' +
            'each step. Fixed slopes are maintained throughout given the three-occasion design\'s ' +
            'documented downward bias on tau11 (Heisig and Schaeffer, 2019), which precludes ' +
            'formal random-slope significance tests while allowing effect-size-based evaluation ' +
            'of within-person variance.'
    },
    's-effects': {
        curious:
            'The forest plot is a visual scorecard of "how much does each predictor actually ' +
            'move the needle?" The bars show pseudo-d values, which tell you how many standard ' +
            'deviations of change in turnover thinking are associated with each predictor. ' +
            'Physical fatigue and emotional exhaustion have the largest effects, around 0.8 to ' +
            '1.0, which researchers consider large. Competence frustration is meaningful too. ' +
            'Notably, autonomy frustration and relatedness frustration barely register at the ' +
            'within-day level.',
        business:
            'Physical fatigue and emotional exhaustion are the strongest within-day predictors, ' +
            'with effect sizes in the large range (pseudo-d roughly 0.8 to 1.0). Competence ' +
            'frustration adds a moderate independent contribution. Autonomy and relatedness ' +
            'frustration do not show direct same-shift effects on turnover thinking, though they ' +
            'may matter over longer timeframes through accumulated burnout. ' +
            'The chronic between-person effects are even larger, reinforcing that addressing ' +
            'baseline conditions remains the highest-leverage intervention.',
        expert:
            'Pseudo-d is computed as the standardized mean difference relative to the ' +
            'level-specific DV standard deviation, preserving interpretability within each ' +
            'level\'s variance metric and avoiding conflation across levels. Between-person ' +
            'pseudo-d values exceed L1 values as expected given the ICC. ' +
            'The forest plot shows focal predictors only; structural controls (recruitment ' +
            'source, affect) are excluded. CIs reflect lmer fixed-effects uncertainty and do ' +
            'not incorporate random-effects variance, which was fixed for slopes throughout.'
    },
    's-hypotheses': {
        curious:
            'Researchers lay out their predictions before collecting data, then check whether ' +
            'the data agreed. 7 of 17 predictions were supported. That is not a failure rate; ' +
            'that is how science works. The burnout findings held in both their physical and ' +
            'emotional forms, within the same day and in long-term averages. ' +
            'Certain psychological frustrations (feeling blocked from autonomy or social ' +
            'connection) did not predict same-day turnover thoughts directly, which tells us ' +
            'something important about which resources are most immediately tied to withdrawal.',
        business:
            '7 of 17 hypotheses were confirmed. The supported ones include the burnout pathways ' +
            '(physical fatigue and emotional exhaustion, both within-day and as chronic averages), ' +
            'job satisfaction, and provisionally psychological contract breach (p = .050). ' +
            'The unsupported ones are equally informative: meeting load did not amplify effects ' +
            '(the sample averaged less than one meeting per four-hour window, too low for a fair ' +
            'test), and autonomy and relatedness frustration showed no direct same-day path to ' +
            'withdrawal. The confirmed findings are ready for organizational translation.',
        expert:
            'Hypothesis reconciliation condensed 20 raw rows to 17 directional tests by ' +
            'excluding the prerequisite ICC row and collapsing H3 moderation sub-rows. ' +
            'The 7/17 support rate reflects partial SDT need frustration evidence (competence ' +
            'supported at L1, autonomy and relatedness null at both levels), full COR burnout ' +
            'pathway support (PF and EE at L1 and L2), and provisional PC breach support ' +
            '(p = .050, power approximately .62). ' +
            'H3 moderation nulls are interpreted against structural floor effects (mean meetings ' +
            '< 1 per four-hour window) rather than as evidence against the resource-sensitization ' +
            'mechanism.'
    },
    's-discussion': {
        curious:
            'The plain-language bottom line: how you physically and emotionally feel during ' +
            'your workday, specifically whether you are tired, emotionally drained, or blocked ' +
            'from doing your job well, directly affects whether you are thinking about quitting ' +
            'on that same day. The stable part of who you are (general job satisfaction, chronic ' +
            'burnout level) matters even more in total. But the daily part is real and responsive. ' +
            'Withdrawal cognition is not just a trait you have; it is something your workday ' +
            'does to you, hour by hour.',
        business:
            'Two levers drive turnover risk. The chronic lever (job satisfaction, chronic burnout, ' +
            'psychological contract) accounts for most variance and requires long-term ' +
            'organizational investment. The within-day lever (daily fatigue spikes, emotional ' +
            'drain, competence blocks) is more acute, more immediate, and more responsive to ' +
            'operational decisions. ' +
            'A manager who reduces mid-shift load spikes and competence interference has a ' +
            'same-day opportunity that annual surveys cannot see.',
        expert:
            'The discussion advances a facet-differentiated revision to the burnout-withdrawal ' +
            'link: PF, EE, and competence frustration carry the within-day signal; autonomy ' +
            'and relatedness frustration do not, consistent with a resource-instrumental account ' +
            'where competence thwarting has direct exchange-relevant implications within a shift. ' +
            'The contrary CW coefficient under the full within-day model is attributed to ' +
            'suppression driven by the PF-CW correlation (.64 at L2) rather than a protective ' +
            'effect. The 79% between-person ICC grounds the within-day effects as bounded and ' +
            'operating inside a structurally constrained variance pool.'
    },
    's-limitations': {
        curious:
            'Every study has limits on what it can conclude, and good science is honest about ' +
            'them. The most important ones here are: not enough participants to be certain about ' +
            'some smaller effects; only three check-ins per day (so faster-moving feelings in ' +
            'the day might be invisible); and the sample was mostly college-educated knowledge ' +
            'workers, so the findings may not apply equally to people in physically demanding ' +
            'or service jobs. The fact that the study names these clearly is a sign of ' +
            'methodological integrity.',
        business:
            'The main practical caveat is sample composition: the study captures knowledge ' +
            'workers, not the full workforce. Before applying these findings to frontline, ' +
            'hourly, or manual roles, replication in those contexts is prudent. ' +
            'Two specific findings (psychological contract breach and competence frustration) ' +
            'should be treated as directional signals rather than confirmed effects given the ' +
            'power shortfall. The overall pattern (burnout predicts same-day turnover thinking) ' +
            'is robust across all analyses.',
        expert:
            'The primary threat is statistical power: N = 336 (42% of target N = 800) places ' +
            'PC breach and competence frustration in the .62 to .84 power range, requiring ' +
            'provisional interpretation. Three occasions impose downward bias on tau11 (Heisig ' +
            'and Schaeffer, 2019) that necessitated fixed-slope models throughout, foreclosing ' +
            'formal moderation tests. Additional constraints: survivorship conditioning on full ' +
            'compliance, single-item TI criterion (no ICC-based reliability), recruitment-source ' +
            'slope homogeneity assumed but untested, and the analytical sample bounds ' +
            'generalizability to educated remote workers rather than hourly or frontline ' +
            'populations.'
    }
};

var SECTION_NAMES = {
    's-about':       '00 About the Researcher',
    's-study':       '01 The Study',
    's-sample':      '02 The Sample',
    's-cofluct':     '03 Correlations',
    's-variance':    '04 Variance Story',
    's-measurement': '05 Measurement',
    's-models':      '06 Model Explorer',
    's-effects':     '07 Effect Sizes',
    's-hypotheses':  '08 Hypotheses',
    's-discussion':  '09 Discussion',
    's-limitations': '10 Limitations'
};

// ---------------------------------------------------------------------------
// Explain panel initialization
// ---------------------------------------------------------------------------

function initExplainPanel() {
    // Build FAB (floating action button with thought-bubble dots)
    var fab = document.createElement('div');
    fab.id = 'explain-fab';
    fab.className = 'explain-fab';
    fab.innerHTML =
        '<div class="explain-dots"><span></span><span></span><span></span></div>' +
        '<button class="explain-btn" id="explain-btn" ' +
        '  aria-label="Open plain-language explanation" ' +
        '  aria-expanded="false" aria-controls="explain-panel">' +
        '  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
        '    stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>' +
        '  </svg>' +
        '  Explain it to me' +
        '</button>';

    // Build panel
    var panel = document.createElement('div');
    panel.id = 'explain-panel';
    panel.className = 'explain-panel';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Plain-language explanation');
    panel.setAttribute('aria-hidden', 'true');
    panel.innerHTML =
        '<div class="explain-panel-inner">' +
        '  <div class="explain-head">' +
        '    <span class="explain-head-label">Explain it to me like&hellip;</span>' +
        '    <button class="explain-close" id="explain-close" aria-label="Close explanation">' +
        '      &#x2715;' +
        '    </button>' +
        '  </div>' +
        '  <div class="explain-section-tag" id="explain-section-tag"></div>' +
        '  <div class="explain-tabs" role="tablist" aria-label="Audience level">' +
        '    <button class="explain-tab active" data-level="curious"  role="tab" aria-selected="true"  tabindex="0">Curious Mind</button>' +
        '    <button class="explain-tab"        data-level="business" role="tab" aria-selected="false" tabindex="-1">Business Impact</button>' +
        '    <button class="explain-tab"        data-level="expert"   role="tab" aria-selected="false" tabindex="-1">Deep Dive</button>' +
        '  </div>' +
        '  <div class="explain-body" id="explain-body" role="tabpanel"></div>' +
        '</div>';

    document.body.appendChild(panel);
    document.body.appendChild(fab);

    var btn      = document.getElementById('explain-btn');
    var closeBtn = document.getElementById('explain-close');
    var activeLevel = storageGet('explainLevel') || 'curious';

    setExplainLevel(activeLevel);

    function openPanel() {
        panel.classList.add('open');
        fab.classList.add('panel-open');
        btn.setAttribute('aria-expanded', 'true');
        panel.setAttribute('aria-hidden', 'false');
        refreshExplainContent();
    }

    function closePanel() {
        panel.classList.remove('open');
        fab.classList.remove('panel-open');
        btn.setAttribute('aria-expanded', 'false');
        panel.setAttribute('aria-hidden', 'true');
    }

    btn.addEventListener('click', function() {
        if (panel.classList.contains('open')) { closePanel(); } else { openPanel(); }
    });

    closeBtn.addEventListener('click', function() { closePanel(); btn.focus(); });

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && panel.classList.contains('open')) {
            closePanel();
            btn.focus();
        }
    });

    var explainTabs = Array.prototype.slice.call(panel.querySelectorAll('.explain-tab'));
    explainTabs.forEach(function(tab) {
        tab.addEventListener('click', function() { setExplainLevel(tab.dataset.level); });
        tab.addEventListener('keydown', function(e) {
            var idx = explainTabs.indexOf(tab);
            var nextIdx = idx;
            if (e.key === 'ArrowRight') nextIdx = (idx + 1) % explainTabs.length;
            if (e.key === 'ArrowLeft')  nextIdx = (idx - 1 + explainTabs.length) % explainTabs.length;
            if (e.key === 'Home')       nextIdx = 0;
            if (e.key === 'End')        nextIdx = explainTabs.length - 1;
            if (nextIdx !== idx) {
                e.preventDefault();
                setExplainLevel(explainTabs[nextIdx].dataset.level);
                explainTabs[nextIdx].focus();
            }
        });
    });

    function setExplainLevel(level) {
        activeLevel = level;
        storageSet('explainLevel', level);
        panel.querySelectorAll('.explain-tab').forEach(function(t) {
            var on = t.dataset.level === level;
            t.classList.toggle('active', on);
            t.setAttribute('aria-selected', on ? 'true' : 'false');
            t.setAttribute('tabindex', on ? '0' : '-1');
        });
        refreshExplainContent();
    }

    function refreshExplainContent() {
        var sectionData = EXPLANATIONS[_explainCurrentSection];
        var body  = document.getElementById('explain-body');
        var tag   = document.getElementById('explain-section-tag');
        if (!sectionData || !body) return;
        var text = sectionData[activeLevel] || '';
        body.innerHTML = '<p>' + text + '</p>';
        if (tag) tag.textContent = SECTION_NAMES[_explainCurrentSection] || '';
    }

    // Called from activateSection when the active tab changes
    window._updateExplainSection = function(sectionId) {
        _explainCurrentSection = sectionId;
        if (panel.classList.contains('open')) { refreshExplainContent(); }
    };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function storageGet(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
}

function storageSet(key, value) {
    try { localStorage.setItem(key, value); } catch (e) { /* storage unavailable */ }
}

function escapeHtml(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function(ch) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
}

var fmt  = function(n, d) { d = d == null ? 2 : d; return n == null ? 'N/A' : Number(n).toFixed(d); };
var pct  = function(n, d) { d = d == null ? 1 : d; return n == null ? 'N/A' : Number(n).toFixed(d) + '%'; };

function getChartGrid() {
    return getComputedStyle(document.documentElement).getPropertyValue('--chart-grid').trim() || '#334155';
}

function getChartTextColor() {
    return getComputedStyle(document.documentElement).getPropertyValue('--muted').trim() || '#94a3b8';
}
var fmtP = function(p) {
    if (p == null) return '';
    if (p < 0.001) return '&lt; .001';
    if (p < 0.01)  return '&lt; .01';
    if (p < 0.05)  return '&lt; .05';
    return fmt(p, 3).replace('0.', '.');
};

function removeSkeleton(el) {
    if (el) el.classList.remove('skeleton');
}

function countUp(el, target, decimals, suffix) {
    if (decimals === undefined) decimals = 0;
    if (suffix    === undefined) suffix  = '';
    var duration = 900;
    var start    = performance.now();
    function step(now) {
        var progress = Math.min((now - start) / duration, 1);
        var ease     = 1 - Math.pow(1 - progress, 3);
        var value    = target * ease;
        el.textContent = value.toFixed(decimals) + suffix;
        if (progress < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
}

function setChartDefaults() {
    Chart.defaults.font.family = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
    Chart.defaults.font.size   = 12;
    Chart.defaults.color       = getChartTextColor();
    Chart.defaults.plugins.legend.display = false;
    Chart.defaults.animation.duration     = 700;
}

// ---------------------------------------------------------------------------
// Technical detail toggle
// ---------------------------------------------------------------------------

function initToggle() {
    var STORAGE_KEY = 'dissertation-detail-view';
    var btn  = document.getElementById('detail-toggle');
    var body = document.body;

    if (storageGet(STORAGE_KEY) === '1') {
        body.classList.add('detail-on');
        btn.setAttribute('data-on', '1');
        btn.setAttribute('aria-pressed', 'true');
    }

    btn.addEventListener('click', function() {
        var on = body.classList.toggle('detail-on');
        btn.setAttribute('data-on', on ? '1' : '0');
        btn.setAttribute('aria-pressed', on ? 'true' : 'false');
        storageSet(STORAGE_KEY, on ? '1' : '0');
    });
}

// ---------------------------------------------------------------------------
// Theme toggle (dark default, light opt-in)
// ---------------------------------------------------------------------------

var MOON_SVG = '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>';
var SUN_SVG  = '<circle cx="12" cy="12" r="5"/>' +
    '<line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/>' +
    '<line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>' +
    '<line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/>' +
    '<line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>';

function applyThemeButton(isLight) {
    var btn   = document.getElementById('theme-toggle');
    var icon  = document.getElementById('theme-icon');
    var label = document.getElementById('theme-label');
    if (!btn) return;
    btn.dataset.mode = isLight ? 'light' : 'dark';
    if (icon)  icon.innerHTML  = isLight ? MOON_SVG : SUN_SVG;
    if (label) label.textContent = isLight ? 'Dark' : 'Light';
    btn.setAttribute('title',       isLight ? 'Switch to dark mode' : 'Switch to light mode');
    btn.setAttribute('aria-label',  isLight ? 'Switch to dark mode' : 'Switch to light mode');
}

function refreshChartsForTheme() {
    setChartDefaults();
    if (!_dashData) return;
    // Re-render forest plot if it exists
    if (forestChart) {
        var activeEsBtn = document.querySelector('.corr-btn[data-esmodel].active');
        var model = activeEsBtn ? activeEsBtn.dataset.esmodel : 'Model 5: L1 + L2 Study Variables';
        renderForest(_dashData, model);
    }
    // Re-render demo chart if it was initialized
    if (rendered['s-sample']) {
        var activeDemo = document.querySelector('.demo-sel-btn.active');
        if (activeDemo && typeof renderDemoChartGlobal === 'function') {
            renderDemoChartGlobal(activeDemo.dataset.var);
        }
    }
}

function initTheme() {
    var STORAGE_KEY = 'dissertation-theme';
    var btn  = document.getElementById('theme-toggle');
    var body = document.body;

    var isLight = storageGet(STORAGE_KEY) === 'light';
    if (isLight) body.classList.add('light-mode');
    applyThemeButton(isLight);

    if (btn) {
        btn.addEventListener('click', function() {
            var nowLight = body.classList.toggle('light-mode');
            storageSet(STORAGE_KEY, nowLight ? 'light' : 'dark');
            applyThemeButton(nowLight);
            requestAnimationFrame(refreshChartsForTheme);
        });
    }
}

// ---------------------------------------------------------------------------
// Sidebar toggle: pushes main content rather than overlaying it, so nothing
// is ever hidden underneath. Defaults open on wider viewports, closed on
// narrow ones; preference persists once the user toggles it explicitly.
// ---------------------------------------------------------------------------

function initSidebar() {
    var STORAGE_KEY = 'dissertation-sidebar-open';
    var body    = document.body;
    var toggle  = document.getElementById('sidebar-toggle');
    var sidebar = document.getElementById('sidebar');
    if (!toggle || !sidebar) return;

    var stored      = storageGet(STORAGE_KEY);
    var defaultOpen = window.innerWidth > 640;
    var isOpen      = stored === '1' ? true : stored === '0' ? false : defaultOpen;

    function applyState(open) {
        body.classList.toggle('sidebar-open', open);
        toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        sidebar.setAttribute('aria-hidden', open ? 'false' : 'true');
    }

    applyState(isOpen);

    toggle.addEventListener('click', function() {
        isOpen = !isOpen;
        storageSet(STORAGE_KEY, isOpen ? '1' : '0');
        applyState(isOpen);
    });
}

// ---------------------------------------------------------------------------
// Footer-avoidance: the "Explain it to me" FAB is fixed to the viewport, so
// as the footer scrolls into view it would otherwise sit on top of the data
// freeze date / OSF / GitHub links. Nudge the FAB and panel upward by
// however much the footer currently intrudes into the viewport.
// ---------------------------------------------------------------------------

function initFooterAvoidance() {
    var footer = document.querySelector('footer');
    var fab    = document.getElementById('explain-fab');
    var panel  = document.getElementById('explain-panel');
    if (!footer || !fab) return;

    function update() {
        var intrusion = window.innerHeight - footer.getBoundingClientRect().top;
        var offset    = intrusion > 0 ? intrusion + 16 : 0;
        fab.style.bottom = 'calc(1.5rem + ' + offset + 'px)';
        if (panel) panel.style.bottom = 'calc(5.25rem + ' + offset + 'px)';
    }

    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update);
    update();
}

// ---------------------------------------------------------------------------
// Tab system
// ---------------------------------------------------------------------------

var SECTIONS = ['s-about', 's-study', 's-sample', 's-cofluct', 's-variance', 's-measurement', 's-models', 's-effects', 's-hypotheses', 's-discussion', 's-limitations'];
var rendered  = {};

function activateSection(id, data, skipAnimation) {
    var tabs     = document.querySelectorAll('.nav-tab');
    var sections = document.querySelectorAll('.section-block');

    sections.forEach(function(s) {
        s.classList.remove('active');
        if (skipAnimation) s.style.animationDuration = '0s';
    });

    tabs.forEach(function(t) {
        var isActive = t.dataset.section === id;
        t.classList.toggle('active', isActive);
        t.setAttribute('aria-selected', isActive ? 'true' : 'false');
    });

    var target = document.getElementById(id);
    if (!target) return;

    if (skipAnimation) {
        target.style.animationDuration = '0s';
        target.classList.add('active');
        requestAnimationFrame(function() { target.style.animationDuration = ''; });
    } else {
        target.classList.add('active');
    }

    // Lazy-render chart sections on first visit
    if (!rendered[id]) {
        rendered[id] = true;
        requestAnimationFrame(function() {
            if (id === 's-sample')  renderSample(data);
            if (id === 's-effects') initEffects(data);
        });
    }

    // Update URL hash without triggering scroll
    try {
        history.replaceState(null, '', '#' + id);
    } catch (e) { /* ignore */ }

    // Sync explain panel content to the newly active section
    if (window._updateExplainSection) window._updateExplainSection(id);
}

function initTabs(data) {
    var tabs = document.querySelectorAll('.nav-tab');
    tabs.forEach(function(btn) {
        btn.addEventListener('click', function() {
            activateSection(btn.dataset.section, data, false);
        });
    });

    // Keyboard: up/down arrows navigate the vertical sidebar list
    document.getElementById('sidebar').addEventListener('keydown', function(e) {
        var active = document.querySelector('.nav-tab.active');
        var idx    = SECTIONS.indexOf(active ? active.dataset.section : 's-study');
        if ((e.key === 'ArrowDown') && idx < SECTIONS.length - 1) {
            e.preventDefault();
            activateSection(SECTIONS[idx + 1], data, false);
            document.querySelector('[data-section="' + SECTIONS[idx + 1] + '"]').focus();
        }
        if ((e.key === 'ArrowUp') && idx > 0) {
            e.preventDefault();
            activateSection(SECTIONS[idx - 1], data, false);
            document.querySelector('[data-section="' + SECTIONS[idx - 1] + '"]').focus();
        }
        if (e.key === 'Home') {
            e.preventDefault();
            activateSection(SECTIONS[0], data, false);
            document.querySelector('[data-section="' + SECTIONS[0] + '"]').focus();
        }
        if (e.key === 'End') {
            e.preventDefault();
            activateSection(SECTIONS[SECTIONS.length - 1], data, false);
            document.querySelector('[data-section="' + SECTIONS[SECTIONS.length - 1] + '"]').focus();
        }
    });

    // Respect URL hash on load
    var hash = window.location.hash.slice(1);
    if (hash && SECTIONS.indexOf(hash) !== -1) {
        activateSection(hash, data, true);
    }
}

// ---------------------------------------------------------------------------
// Sample / demographics
// ---------------------------------------------------------------------------

function renderSample(data) {
    var meta   = data.meta;
    var sample = data.sample;
    var funnel = data.funnel;

    var nEl   = document.getElementById('val-n');
    var obsEl = document.getElementById('val-obs');
    var ageEl = document.getElementById('val-age');

    if (nEl)   countUp(nEl,   meta.n_participants, 0);
    if (obsEl) countUp(obsEl, meta.n_observations, 0);

    var ageCont = sample.continuous.filter(function(r) { return r.variable === 'age'; })[0];
    if (ageCont && ageEl) {
        countUp(ageEl, ageCont.mean, 1);
        var sub = document.getElementById('val-age-sub');
        if (sub) sub.textContent = 'years (SD = ' + fmt(ageCont.sd, 2) + ')';
        removeSkeleton(ageEl);
    }

    var lead = document.getElementById('sample-lead');
    if (lead) lead.textContent =
        meta.n_participants + ' full-time employees completed ' + meta.n_observations +
        ' experience sampling surveys across the workday.';

    // Funnel
    var funnelEl = document.getElementById('funnel-steps');
    if (funnelEl) {
        var max = funnel.steps[0].n;
        funnelEl.innerHTML = funnel.steps.map(function(s) {
            return '<div class="funnel-step">' +
                '<span class="funnel-label">' + escapeHtml(s.label) + '</span>' +
                '<div class="bar-track"><div class="bar-fill" data-target="' +
                    (s.n / max * 100).toFixed(1) + '"></div></div>' +
                '<span class="funnel-stat"><strong>' + s.n.toLocaleString() + '</strong></span>' +
                '</div>';
        }).join('');
        requestAnimationFrame(function() {
            funnelEl.querySelectorAll('.bar-fill').forEach(function(el) {
                el.style.width = el.dataset.target + '%';
            });
        });
    }

    // Demographic chart with selector
    var demoEl = document.getElementById('demo-grid');
    if (!demoEl) return;

    // Keys must match variable names in sample.categorical (from eda_10_table1_categorical.csv).
    // remap: display labels for raw level values that are codes rather than readable strings.
    var DEMO_OPTIONS = [
        { key: 'ethnicity',          label: 'Ethnicity / Race' },
        { key: 'gender',             label: 'Gender Identity' },
        { key: 'edu_lvl',            label: 'Education' },
        { key: 'is_remote',          label: 'Work Arrangement',
          remap: { 'TRUE': 'Remote', 'FALSE': 'On-site' } },
        { key: 'recruitment_source', label: 'Recruitment Source',
          remap: { 'cloudresearch': 'CloudResearch', 'snowball': 'Snowball' } },
    ];

    demoEl.innerHTML =
        '<div id="demo-selector" class="demo-selector"></div>' +
        '<div class="card demo-chart-card" style="padding:1.25rem 1.5rem">' +
            '<div class="chart-wrap" style="min-height:260px">' +
                '<canvas id="demo-chart-canvas" aria-label="Demographic distribution"></canvas>' +
            '</div>' +
        '</div>';

    var activeDemoVar   = 'ethnicity';
    var activeDemoChart = null;

    // Expose so refreshChartsForTheme can trigger a redraw
    renderDemoChartGlobal = function(varName) { renderDemoChart(varName || activeDemoVar); };

    function renderDemoChart(varName) {
        var opt  = DEMO_OPTIONS.filter(function(d) { return d.key === varName; })[0] || {};
        var remap = opt.remap || {};
        var rows = sample.categorical.filter(function(r) { return r.variable === varName; });
        if (!rows.length) return;
        if (activeDemoChart) { activeDemoChart.destroy(); activeDemoChart = null; }
        var ctx = document.getElementById('demo-chart-canvas');
        if (!ctx) return;
        activeDemoChart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: rows.map(function(r) { return remap[r.level] || r.level; }),
                datasets: [{
                    data:            rows.map(function(r) { return r.pct; }),
                    backgroundColor: '#cc0000',
                    borderRadius:    4,
                    borderSkipped:   false,
                }],
            },
            options: {
                indexAxis:           'y',
                responsive:          true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        max:   100,
                        ticks: { callback: function(v) { return v + '%'; } },
                        grid:  { color: getChartGrid() },
                    },
                    y: { ticks: { font: { size: 11 } } },
                },
                plugins: {
                    tooltip: {
                        callbacks: {
                            label: function(ctx) {
                                var row = rows[ctx.dataIndex];
                                var count = row.n != null ? '  (n = ' + row.n + ')' : '';
                                return ' ' + ctx.raw.toFixed(1) + '%' + count;
                            },
                        },
                    },
                },
            },
        });
    }

    var selectorEl = document.getElementById('demo-selector');
    if (selectorEl) {
        selectorEl.innerHTML = DEMO_OPTIONS.map(function(d) {
            return '<button class="demo-sel-btn' + (d.key === activeDemoVar ? ' active' : '') +
                   '" data-var="' + d.key + '">' + d.label + '</button>';
        }).join('');
        selectorEl.querySelectorAll('.demo-sel-btn').forEach(function(btn) {
            btn.addEventListener('click', function() {
                selectorEl.querySelectorAll('.demo-sel-btn').forEach(function(b) { b.classList.remove('active'); });
                btn.classList.add('active');
                activeDemoVar = btn.dataset.var;
                renderDemoChart(activeDemoVar);
            });
        });
    }

    renderDemoChart(activeDemoVar);
}

// ---------------------------------------------------------------------------
// Correlation matrix
// ---------------------------------------------------------------------------

var CORR_SHORT = {
    timepoint:               'Time',
    pf_mean:                 'PF',
    cw_mean:                 'CW',
    ee_mean:                 'EE',
    comp_mean:               'Comp',
    auto_mean:               'Auto',
    relt_mean:               'Relt',
    atcb_mean:               'ATCB',
    meetings_count:          'Mtg#',
    meetings_time:           'MtgT',
    turnover_intention_mean: 'TI',
    pa_mean:                 'PA',
    na_mean:                 'NA',
    br_mean:                 'Breach',
    vio_mean:                'Viol',
    js_mean:                 'JS',
    jis_mean:                'JIS',
    des_mean:                'DES',
    age:                     'Age',
};

// Omega reliability lookup by variable key and correlation mode.
// Within diagonal shows L1_within omega; between diagonal shows L2 omega.
var OMEGA_WITHIN = {
    pf_mean:   0.809,
    cw_mean:   0.844,
    ee_mean:   0.607,
    comp_mean: 0.563,
    auto_mean: 0.554,
    relt_mean: 0.619,
    atcb_mean: 0.483,
};
var OMEGA_BETWEEN = {
    pa_mean:  0.774,
    na_mean:  0.817,
    br_mean:  0.942,
    vio_mean: 0.919,
    des_mean: 0.881,
};

function renderCorrTable(corr, mode) {
    var data  = mode === 'within' ? corr.within : corr.between;
    var vars  = data.variables;
    var pairs = data.pairs;
    var omegaMap = mode === 'within' ? OMEGA_WITHIN : OMEGA_BETWEEN;

    var lookup = {};
    pairs.forEach(function(p) {
        lookup[p.row + '|' + p.col] = p;
        lookup[p.col + '|' + p.row] = p;
    });

    var thead = document.getElementById('corr-thead');
    var tbody = document.getElementById('corr-tbody');
    if (!thead || !tbody) return;

    var keys = vars.map(function(v) { return v.key; });

    function short(k) { return CORR_SHORT[k] || k; }
    function labelOf(k) {
        var v = vars.filter(function(x) { return x.key === k; })[0];
        return v ? v.label : k;
    }

    thead.innerHTML = '<tr><th></th>' +
        keys.map(function(k) {
            return '<th title="' + labelOf(k) + '">' + short(k) + '</th>';
        }).join('') + '</tr>';

    tbody.innerHTML = keys.map(function(rowKey, i) {
        var rowLabel = labelOf(rowKey);
        var cells = keys.map(function(colKey, j) {
            if (i === j) {
                var omega = omegaMap[rowKey];
                if (omega != null) {
                    var omegaDisp = omega.toFixed(2).replace('0.', '.');
                    return '<td class="corr-omega" title="' + labelOf(rowKey) + ': ω = ' + omega.toFixed(3) + ' (reliability)">' +
                           '<span class="omega-val">' + omegaDisp + '</span>' +
                           '<span class="omega-sym">ω</span></td>';
                }
                return '<td class="corr-diag">&ndash;</td>';
            }
            if (j > i) return '<td class="corr-upper"></td>';
            var pair = lookup[rowKey + '|' + colKey];
            if (!pair || pair.r == null) return '<td></td>';
            var display = pair.r.toFixed(2).replace('0.', '.').replace('-0.', '-.');
            var cls  = pair.sig ? 'corr-cell-sig' : '';
            var star = pair.sig ? '*' : '';
            return '<td class="' + cls + '" title="r = ' + pair.r.toFixed(3) +
                   ', p = ' + (pair.p != null ? pair.p.toFixed(4) : 'NA') + '">' +
                   display + star + '</td>';
        }).join('');
        return '<tr><td class="row-label" title="' + rowLabel + '">' + short(rowKey) + '</td>' + cells + '</tr>';
    }).join('');

    var desc = document.getElementById('corr-description');
    if (desc) {
        if (mode === 'within') {
            desc.innerHTML = '<strong>Within-person correlations</strong> (rmcorr): how each variable tends to ' +
                'move together <em>within the same employee</em> across time points. ' +
                'Diagonal values show ω (omega) reliability estimates. ' +
                'Values marked * are statistically significant (p &lt; .05).';
        } else {
            desc.innerHTML = '<strong>Between-person correlations</strong> (Pearson): associations among ' +
                'employee <em>average</em> scores across the study period. ' +
                'Diagonal values show ω (omega) reliability estimates where available. ' +
                'Values marked * are statistically significant (p &lt; .05).';
        }
    }
}

function initCorr(data) {
    var btns        = document.querySelectorAll('.corr-btn[data-mode]');
    var currentMode = 'within';
    renderCorrTable(data.correlations, currentMode);
    btns.forEach(function(btn) {
        btn.addEventListener('click', function() {
            btns.forEach(function(b) { b.classList.remove('active'); });
            btn.classList.add('active');
            currentMode = btn.dataset.mode;
            renderCorrTable(data.correlations, currentMode);
        });
    });
}

// ---------------------------------------------------------------------------
// Variance story
// ---------------------------------------------------------------------------

function renderVariance(data) {
    var v = data.variance;

    var iccEl    = document.getElementById('val-icc');
    var withinEl = document.getElementById('val-within-pct');
    if (iccEl)    { countUp(iccEl,    v.pct_between_ti, 0, '%'); removeSkeleton(iccEl); }
    if (withinEl) { countUp(withinEl, v.pct_within_ti,  0, '%'); removeSkeleton(withinEl); }

    var lead = document.getElementById('variance-lead');
    if (lead) lead.textContent =
        pct(v.pct_between_ti, 0) + ' of the variance in turnover intentions lies between employees ' +
        '(stable individual differences). The remaining ' + pct(v.pct_within_ti, 0) +
        ' fluctuates within the same person across the workday -- and that is what this study explains.';

    var barsEl = document.getElementById('variance-bars');
    if (!barsEl) return;
    barsEl.innerHTML = v.variables.map(function(row) {
        return '<div class="variance-row">' +
            '<span class="variance-label">' + escapeHtml(row.label) + '</span>' +
            '<div class="variance-track">' +
                '<div class="variance-fill-between" data-target="' + row.pct_between.toFixed(1) + '"></div>' +
            '</div>' +
            '<span class="variance-icc"><strong>' + pct(row.pct_between, 0) + '</strong> between</span>' +
            '</div>';
    }).join('');
    requestAnimationFrame(function() {
        barsEl.querySelectorAll('.variance-fill-between').forEach(function(el) {
            el.style.width = el.dataset.target + '%';
        });
    });

    var calloutHead = document.getElementById('variance-callout-head');
    if (calloutHead) {
        calloutHead.textContent = pct(v.pct_between_ti, 0) + ' between, ' + pct(v.pct_within_ti, 0) + ' within.';
    }
}

// ---------------------------------------------------------------------------
// Model explorer
// ---------------------------------------------------------------------------

var MODEL_SHORT = {
    'Model 0: Unconditional Means':        'M0',
    'Model 1: Fixed Time':                 'M1',
    'Model 2: Random Slope':               'M2',
    'Model 3: L1 Within-Person':           'M3',
    'Model 4: L1 Within + Between':        'M4',
    'Model 5: L1 + L2 Study Variables':    'M5',
    'Model 6: Full Model with Covariates': 'M6',
    'Model 7a: Count x Composites':        'M7a',
    'Model 7b: Time x Composites':         'M7b',
};

function renderModelExplorer(data, selectedModel) {
    var comparison    = data.models.comparison;
    var fixed_effects = data.models.fixed_effects;
    var selectorEl    = document.getElementById('model-selector');
    var fitEl         = document.getElementById('model-fit-stats');
    var tbodyEl       = document.getElementById('fx-tbody');
    if (!selectorEl || !fitEl || !tbodyEl) return;

    var allModels = Object.keys(fixed_effects);
    selectorEl.innerHTML = allModels.map(function(m) {
        return '<button class="model-btn' + (m === selectedModel ? ' active' : '') +
               '" data-model="' + m + '">' + (MODEL_SHORT[m] || m) + '</button>';
    }).join('');

    selectorEl.querySelectorAll('.model-btn').forEach(function(btn) {
        btn.addEventListener('click', function() { renderModelExplorer(data, btn.dataset.model); });
    });

    var fitRow = comparison.filter(function(r) { return r.model === selectedModel; })[0];
    if (fitEl) {
        if (fitRow) {
            var fitStats = [
                { label: 'AIC',              value: fmt(fitRow.aic,             0) },
                { label: 'BIC',              value: fmt(fitRow.bic,             0) },
                { label: 'R&sup2; marginal', value: fmt(fitRow.r2_marginal,    3) },
                { label: 'R&sup2; conditional', value: fmt(fitRow.r2_conditional, 3) },
                { label: 'LRT p',            value: fitRow.lrt_p != null ? fmtP(fitRow.lrt_p) : 'N/A' },
            ];
            fitEl.innerHTML = fitStats.map(function(s) {
                return '<div class="fit-stat">' +
                    '<div class="fit-stat-label">' + s.label + '</div>' +
                    '<div class="fit-stat-value">' + s.value + '</div>' +
                    '</div>';
            }).join('');
        } else {
            fitEl.innerHTML = '<p style="font-size:0.8rem;color:var(--muted);grid-column:1/-1">' +
                'Fit statistics not available for interaction models (M7a/M7b). ' +
                'See fixed effects below.</p>';
        }
    }

    var effects = fixed_effects[selectedModel] || [];
    tbodyEl.innerHTML = effects.map(function(e) {
        var sigClass = e.p_value < 0.001 ? 'sig-001' : e.p_value < 0.01 ? 'sig-01' : e.p_value < 0.05 ? 'sig-05' : '';
        var ci = '[' + fmt(e.conf_low, 3) + ', ' + fmt(e.conf_high, 3) + ']';
        return '<tr class="' + sigClass + '">' +
            '<td class="term-label">' + escapeHtml(e.label || e.term) + '</td>' +
            '<td class="numeric">' + fmt(e.estimate, 3) + '</td>' +
            '<td class="numeric">' + fmt(e.std_error, 3) + '</td>' +
            '<td class="numeric">' + fmtP(e.p_value) + '</td>' +
            '<td class="numeric" style="font-size:0.75rem">' + ci + '</td>' +
            '</tr>';
    }).join('');
}

// ---------------------------------------------------------------------------
// Effect sizes (forest plot) - lazy-rendered on first tab visit
// ---------------------------------------------------------------------------

var forestChart = null;

// Structural controls excluded from the forest plot; they are not focal predictors.
// Full fixed-effects tables (including these terms) remain visible on the Model Explorer tab.
var FOREST_EXCLUDE = [
    '(Intercept)',
    'time_c',
    'meetings_count_between',
    'meetings_time_between',
];
function isStructuralControl(term) {
    if (FOREST_EXCLUDE.indexOf(term) !== -1) return true;
    if (term && term.indexOf('recruitment_source') === 0) return true;
    return false;
}

function renderForest(data, modelName) {
    var es = data.effects.level_specific[modelName];
    if (!es) return;

    var ctx = document.getElementById('forest-canvas');
    if (!ctx) return;

    var focal  = es.filter(function(e) { return !isStructuralControl(e.term); });
    var sorted = focal.slice().sort(function(a, b) { return Math.abs(b.pseudo_d) - Math.abs(a.pseudo_d); });
    var labels = sorted.map(function(e) { return e.label; });
    var values = sorted.map(function(e) { return e.pseudo_d; });
    var colors = sorted.map(function(e) { return e.pseudo_d > 0 ? '#cc0000' : '#7c3aed'; });

    if (forestChart) { forestChart.destroy(); forestChart = null; }

    ctx.parentElement.style.minHeight = Math.max(300, sorted.length * 28) + 'px';

    forestChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                data:            values,
                backgroundColor: colors,
                borderRadius:    3,
                borderSkipped:   false,
            }],
        },
        options: {
            indexAxis:           'y',
            responsive:          true,
            maintainAspectRatio: false,
            scales: {
                x: {
                    title: { display: true, text: 'Effect Size (pseudo-d)', color: getChartTextColor(), font: { size: 11 } },
                    grid:  { color: getChartGrid() },
                    ticks: { color: getChartTextColor(), callback: function(v) { return v === 0 ? '0' : fmt(v, 2); } },
                },
                y: { ticks: { color: getChartTextColor(), font: { size: 11 } } },
            },
            plugins: {
                legend: { display: false },
                tooltip: {
                    callbacks: {
                        label: function(ctx) {
                            var e = sorted[ctx.dataIndex];
                            return ' d = ' + fmt(e.pseudo_d, 3) + ' [' + fmt(e.pseudo_d_lo, 3) + ', ' + fmt(e.pseudo_d_hi, 3) + ']';
                        },
                        afterLabel: function(ctx) {
                            var e = sorted[ctx.dataIndex];
                            return ' magnitude: ' + e.magnitude + ' (' + e.level + ')';
                        },
                    },
                },
            },
        },
    });
}

function initEffects(data) {
    var btns         = document.querySelectorAll('.corr-btn[data-esmodel]');
    var currentModel = 'Model 5: L1 + L2 Study Variables';
    renderForest(data, currentModel);
    btns.forEach(function(btn) {
        btn.addEventListener('click', function() {
            btns.forEach(function(b) { b.classList.remove('active'); });
            btn.classList.add('active');
            currentModel = btn.dataset.esmodel;
            renderForest(data, currentModel);
        });
    });
}

// ---------------------------------------------------------------------------
// Hypothesis scorecard
// ---------------------------------------------------------------------------

function renderHypotheses(data, filter) {
    var items           = data.hypotheses.items;
    var supported_count = data.hypotheses.supported_count;
    var total           = data.hypotheses.total;
    var tallyEl         = document.getElementById('hyp-tally');
    var gridEl          = document.getElementById('hyp-grid');
    if (!tallyEl || !gridEl) return;

    var visible = items;
    if (filter === 'within')    visible = items.filter(function(h) { return h.level_short === 'within'; });
    if (filter === 'between')   visible = items.filter(function(h) { return h.level_short === 'between'; });
    if (filter === 'supported') visible = items.filter(function(h) { return h.supported; });

    tallyEl.innerHTML =
        'Showing ' + visible.length + ' of ' + total + ' hypotheses: ' +
        '<strong>' + supported_count + ' of ' + total + ' supported</strong> overall';

    gridEl.innerHTML = visible.map(function(h) {
        var badgeClass = h.supported ? 'supported' : 'not-supported';
        var badgeText  = h.supported ? 'Supported' : 'Not supported';
        var cardClass  = h.supported ? 'hyp-card supported' : 'hyp-card';
        var idClass    = h.supported ? 'hyp-id' : 'hyp-id not-supported';
        var levelLabel = h.level_short === 'within' ? 'Within-person (L1)' : 'Between-person (L2)';
        var pLabel     = h.p_value != null ? 'p ' + fmtP(h.p_value) : '';
        var estLabel   = h.estimate != null ? 'b = ' + fmt(h.estimate, 3) : '';
        var metaParts  = [levelLabel, estLabel, pLabel].filter(Boolean);
        var metaText   = metaParts.join(' &nbsp;&middot;&nbsp; ');

        return '<div class="' + cardClass + '">' +
            '<div class="hyp-card-top">' +
                '<span class="' + idClass + '">' + h.id + '</span>' +
                '<span class="hyp-badge ' + badgeClass + '">' + badgeText + '</span>' +
            '</div>' +
            '<p class="hyp-desc">' + h.plain_description + '</p>' +
            '<p class="hyp-meta">' + metaText + '</p>' +
            '</div>';
    }).join('');
}

// ---------------------------------------------------------------------------
// Measurement model
// ---------------------------------------------------------------------------

function renderMeasurement(data) {
    var mmt = data.measurement;
    if (!mmt) return;

    // Populate stat cards from JSON data
    var fi = mmt.fit_indices || [];
    var l1 = fi.filter(function(f) { return f.model && f.model.indexOf('L1') === 0; })[0];
    var l2 = fi.filter(function(f) { return f.model && f.model.indexOf('L2') === 0; })[0];
    if (l1) {
        var l1cfi = document.getElementById('mmt-l1-cfi');
        var l1sub = document.getElementById('mmt-l1-sub');
        if (l1cfi) l1cfi.textContent = l1.cfi.toFixed(3).replace('0.', '.');
        if (l1sub) l1sub.textContent = 'CFI · RMSEA = ' + l1.rmsea.toFixed(3).replace('0.', '.');
    }
    if (l2) {
        var l2cfi = document.getElementById('mmt-l2-cfi');
        var l2sub = document.getElementById('mmt-l2-sub');
        if (l2cfi) l2cfi.textContent = l2.cfi.toFixed(3).replace('0.', '.');
        if (l2sub) l2sub.textContent = 'CFI · RMSEA = ' + l2.rmsea.toFixed(3).replace('0.', '.');
    }
    var markerVal = document.getElementById('mmt-marker-val');
    if (markerVal) markerVal.textContent = mmt.marker_unbiased ? 'None detected' : 'Bias detected';
    var invVal = document.getElementById('mmt-inv-val');
    if (invVal) invVal.textContent = mmt.metric_invariance_supported ? 'Supported' : 'Not supported';

    // Update callout p-values from LRT data
    var markerLrt = (mmt.marker_lrt || []).filter(function(r) { return r.conclusion === 'unbiased'; })[0];
    var mmpEl = document.getElementById('mmt-marker-p');
    if (mmpEl && markerLrt) mmpEl.textContent = markerLrt.p_value >= 1 ? '1.00' : markerLrt.p_value.toFixed(2);
    var invRows = mmt.metric_invariance || [];
    var metricRow = invRows.filter(function(r) { return r.model && r.model.toLowerCase() === 'metric'; })[0];
    var mipEl = document.getElementById('mmt-inv-p');
    if (mipEl && metricRow && metricRow.p_diff != null) {
        mipEl.textContent = metricRow.p_diff >= 1 ? '1.00' : metricRow.p_diff.toFixed(2);
    }

    // Marker correlation bars
    var barsEl = document.getElementById('mmt-marker-bars');
    if (barsEl && mmt.marker_evidence) {
        var maxAbs = 0.1; // fixed scale so near-zero is visually obvious
        barsEl.innerHTML = mmt.marker_evidence.map(function(e) {
            var r = e.rmcorr_r;
            var pct = Math.min(Math.abs(r) / maxAbs * 100, 100);
            var barColor = 'var(--muted)';
            var rStr = (r >= 0 ? '+' : '') + r.toFixed(3);
            return '<div class="mmt-bar-row">' +
                '<span class="mmt-bar-label">' + e.label + '</span>' +
                '<div class="mmt-bar-track">' +
                    '<div class="mmt-bar-fill" style="width:' + pct + '%;background:' + barColor + '"></div>' +
                '</div>' +
                '<span class="mmt-bar-val">' + rStr + '</span>' +
                '<span class="mmt-bar-badge">near zero</span>' +
                '</div>';
        }).join('');
    }

    // Fit indices table (tech detail)
    var fitEl = document.getElementById('mmt-fit-table');
    if (fitEl && mmt.fit_indices) {
        fitEl.innerHTML = '<table class="fx-table" style="width:100%;font-size:0.78rem">' +
            '<thead><tr><th>Model</th><th>CFI</th><th>TLI</th><th>RMSEA</th><th>SRMR (within)</th><th>SRMR (between)</th></tr></thead>' +
            '<tbody>' +
            mmt.fit_indices.map(function(fi) {
                var srmrW = fi.srmr_within != null ? fi.srmr_within.toFixed(3) : (fi.srmr != null ? fi.srmr.toFixed(3) : 'N/A');
                var srmrB = fi.srmr_between != null ? fi.srmr_between.toFixed(3) : 'N/A';
                return '<tr><td>' + fi.model + '</td>' +
                    '<td>' + fi.cfi.toFixed(3) + '</td>' +
                    '<td>' + fi.tli.toFixed(3) + '</td>' +
                    '<td>' + fi.rmsea.toFixed(3) + ' [' + fi.rmsea_lo.toFixed(3) + ', ' + fi.rmsea_hi.toFixed(3) + ']</td>' +
                    '<td>' + srmrW + '</td>' +
                    '<td>' + srmrB + '</td></tr>';
            }).join('') +
            '</tbody></table>';
    }

    // LRT table (tech detail)
    var lrtEl = document.getElementById('mmt-lrt-table');
    if (lrtEl && mmt.marker_lrt) {
        lrtEl.innerHTML = '<table class="fx-table" style="width:100%;font-size:0.78rem">' +
            '<thead><tr><th>Comparison</th><th>SB chi-sq</th><th>df</th><th>p</th><th>Conclusion</th></tr></thead>' +
            '<tbody>' +
            mmt.marker_lrt.map(function(r) {
                var concCls = r.conclusion === 'unbiased' ? 'style="color:var(--ncstate-red)"' : '';
                return '<tr><td style="font-size:0.75rem">' + r.comparison + '</td>' +
                    '<td>' + r.delta_chisq_sb.toFixed(2) + '</td>' +
                    '<td>' + r.delta_df + '</td>' +
                    '<td>' + (r.p_value < 0.001 ? '< .001' : r.p_value.toFixed(3)) + '</td>' +
                    '<td ' + concCls + '>' + r.conclusion + '</td></tr>';
            }).join('') +
            '</tbody></table>';
    }

    // Metric invariance table (tech detail)
    var invEl = document.getElementById('mmt-inv-table');
    if (invEl && mmt.metric_invariance) {
        invEl.innerHTML = '<table class="fx-table" style="width:100%;font-size:0.78rem">' +
            '<thead><tr><th>Model</th><th>chi-sq</th><th>df</th><th>delta chi-sq</th><th>delta df</th><th>p</th><th>Result</th></tr></thead>' +
            '<tbody>' +
            mmt.metric_invariance.map(function(r) {
                var pStr = r.p_diff != null ? (r.p_diff < 0.001 ? '< .001' : r.p_diff.toFixed(3)) : 'N/A';
                var dcsq = r.delta_chi2 != null ? r.delta_chi2.toFixed(2) : 'N/A';
                var ddf  = r.delta_df  != null ? r.delta_df  : 'N/A';
                var res  = r.result || 'N/A';
                return '<tr><td>' + r.model + '</td>' +
                    '<td>' + r.chi2.toFixed(2) + '</td>' +
                    '<td>' + r.df + '</td>' +
                    '<td>' + dcsq + '</td>' +
                    '<td>' + ddf + '</td>' +
                    '<td>' + pStr + '</td>' +
                    '<td style="color:var(--ncstate-red)">' + res + '</td></tr>';
            }).join('') +
            '</tbody></table>';
    }
}

function initHypotheses(data) {
    var btns          = document.querySelectorAll('.hyp-filter-btn');
    var currentFilter = 'all';
    renderHypotheses(data, currentFilter);
    btns.forEach(function(btn) {
        btn.addEventListener('click', function() {
            btns.forEach(function(b) { b.classList.remove('active'); });
            btn.classList.add('active');
            currentFilter = btn.dataset.filter;
            renderHypotheses(data, currentFilter);
        });
    });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function init() {
    initTheme();
    setChartDefaults();
    initToggle();
    initSidebar();

    var data;
    try {
        var res = await fetch('data/dashboard.json');
        if (!res.ok) throw new Error('HTTP ' + res.status);
        data = await res.json();
        _dashData = data;
    } catch (err) {
        var banner = document.getElementById('error-banner');
        if (banner) {
            banner.style.display = 'block';
            banner.textContent   =
                'Could not load dashboard data: ' + err.message +
                '. Serve the dashboard/ directory (netlify dev or python -m http.server).';
        }
        return;
    }

    // Explain panel (pure DOM, no data dependency)
    initExplainPanel();
    initFooterAvoidance();

    // Pre-render all non-chart sections immediately (canvas-free, safe when hidden)
    initCorr(data);
    renderVariance(data);
    renderMeasurement(data);
    renderModelExplorer(data, 'Model 5: L1 + L2 Study Variables');
    initHypotheses(data);

    // Tab system + lazy chart rendering (Sample + Effects render on first tab visit)
    initTabs(data);

    // Activate initial section
    var hash = window.location.hash.slice(1);
    var initial = (hash && SECTIONS.indexOf(hash) !== -1) ? hash : 's-study';
    activateSection(initial, data, true);
}

document.addEventListener('DOMContentLoaded', init);

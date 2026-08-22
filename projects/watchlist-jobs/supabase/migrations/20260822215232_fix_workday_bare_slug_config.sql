-- WorkdayScraper.afetch() requires company_slug to be the full careers URL
-- (https://{tenant}.wdN.myworkdayjobs.com/{site}) -- it parses the tenant,
-- wdN instance, and site back out of the URL at fetch time. These three rows
-- were entered as a bare "tenant/site" slug with no scheme/host, so every
-- pull failed with "Workday URL must look like ... ", surfaced by the new
-- pull_failures classifier as error_code=CONFIG.
--
-- The tenant/site portion was already correct; each fix below just adds the
-- missing https://{tenant}.wdN.myworkdayjobs.com/ prefix. wdN instance
-- numbers and job counts confirmed live against the Workday CXS jobs API
-- before this migration was written (accuray.wd5 -> 30 jobs, acelero.wd1 ->
-- 20 jobs, abercrombiekent.wd12 -> 9 jobs).
update watchlist_companies
set slug = 'https://accuray.wd5.myworkdayjobs.com/external'
where company = 'Accuray' and ats = 'workday';

update watchlist_companies
set slug = 'https://acelero.wd1.myworkdayjobs.com/shineearlylearningcareers'
where company = 'Shine Early Learning' and ats = 'workday';

update watchlist_companies
set slug = 'https://abercrombiekent.wd12.myworkdayjobs.com/crystalcruises_careers'
where company = 'A&K Travel Group' and ats = 'workday';

/*
 * Default Apple News+ publisher allowlist.
 *
 * These are domains whose articles are generally available in an Apple News+
 * subscription. The list is deliberately conservative: a wrong entry means you
 * get yanked to the News "Today" screen, because the macOS share service
 * reports success even when it cannot resolve the article.
 *
 * The list is only a seed. Anything you add via the toolbar button is stored in
 * extension storage and takes precedence.
 */
self.DEFAULT_PUBLISHERS = [
  // News / business
  'wsj.com',
  'latimes.com',
  'theatlantic.com',
  'newyorker.com',
  'time.com',
  'newsweek.com',
  'thedailybeast.com',
  'theweek.com',
  'fortune.com',
  'inc.com',
  'fastcompany.com',
  'entrepreneur.com',
  'nymag.com',
  'vulture.com',
  'thecut.com',

  // Tech / science
  'wired.com',
  'technologyreview.com',
  'newscientist.com',
  'popsci.com',
  'discovermagazine.com',
  'smithsonianmag.com',
  'popularmechanics.com',

  // Culture / entertainment
  'vanityfair.com',
  'rollingstone.com',
  'thehollywoodreporter.com',
  'billboard.com',
  'variety.com',
  'people.com',
  'us.hellomagazine.com',

  // Style / living
  'vogue.com',
  'gq.com',
  'esquire.com',
  'harpersbazaar.com',
  'elle.com',
  'cosmopolitan.com',
  'goodhousekeeping.com',
  'architecturaldigest.com',
  'cntraveler.com',
  'bonappetit.com',
  'foodandwine.com',
  'travelandleisure.com',
  'realsimple.com',

  // Health / sport / outdoors
  'menshealth.com',
  'womenshealthmag.com',
  'runnersworld.com',
  'bicycling.com',
  'outsideonline.com',
  'si.com',
  'health.com',
  'prevention.com',

  // Auto
  'caranddriver.com',
  'roadandtrack.com',

  // Travel / geo
  'nationalgeographic.com'
];

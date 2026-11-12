// The image of a Pinterest pin, from its link (T10).
//
// Sharing from the Pinterest app often gives Caro a link (pin.it/... or pinterest.com/pin/...)
// instead of the image. The server then opens that page, as a browser would, and takes the
// image the page names as its own (its "og:image" tag), from Pinterest's image site.
//
// Only Pinterest: the server never opens other addresses for a member, so a link cannot make
// it reach anything else (like a computer on the server's own network). Every redirect is
// checked the same way. Pages and images have a size and a time limit.

const PAGE_LIMIT = 3 * 1024 * 1024;
const IMAGE_LIMIT = 20 * 1024 * 1024;
const TIMEOUT_MS = 10 * 1000;
const MAX_REDIRECTS = 5;
const USER_AGENT = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

// Something went wrong getting the image. The message is safe to show in the app.
class LinkError extends Error {}

const NOT_PINTEREST = 'Caro can take the image only from a Pinterest link. Save the image to Photos and share it from there.';
const NO_IMAGE = 'Caro could not get the image from this link. Save the image to Photos and share it from there.';

function parse(link) {
  try {
    const url = new URL(String(link).trim());
    return url.protocol === 'https:' ? url : null;
  } catch {
    return null;
  }
}

// pin.it, pinterest.com, and Pinterest's country sites like nl.pinterest.com or pinterest.co.uk.
function isPinterestPage(url) {
  const host = url.hostname.toLowerCase();
  return host === 'pin.it' || /^([a-z0-9-]+\.)?pinterest\.(com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})$/.test(host);
}

function isPinterestImage(url) {
  return url.hostname.toLowerCase() === 'i.pinimg.com';
}

function isPinterestLink(link) {
  const url = parse(link);
  return Boolean(url && isPinterestPage(url));
}

// Fetches an address, following redirects only to addresses `allowed` accepts. Returns the
// last response and its address.
async function fetchChecked(url, allowed) {
  let current = url;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const res = await fetch(current, {
      redirect: 'manual',
      headers: { 'User-Agent': USER_AGENT, Accept: 'text/html,image/*' },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (res.status >= 300 && res.status < 400 && res.headers.get('location')) {
      const nextUrl = parse(new URL(res.headers.get('location'), current).href);
      if (!nextUrl || !allowed(nextUrl)) throw new LinkError(NO_IMAGE);
      current = nextUrl;
      continue;
    }
    if (!res.ok) throw new LinkError(NO_IMAGE);
    return { res, url: current };
  }
  throw new LinkError(NO_IMAGE);
}

// The body, up to `limit` bytes; more than that is refused.
async function readLimited(res, limit) {
  const declared = Number(res.headers.get('content-length'));
  if (declared > limit) throw new LinkError(NO_IMAGE);
  const chunks = [];
  let size = 0;
  for await (const chunk of res.body) {
    size += chunk.length;
    if (size > limit) throw new LinkError(NO_IMAGE);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

// The address in the page's og:image tag, in either attribute order.
function ogImage(html) {
  const tags = html.match(/<meta\b[^>]*>/gi) || [];
  for (const tag of tags) {
    if (!/(property|name)\s*=\s*["']og:image(:secure_url)?["']/i.test(tag)) continue;
    const content = tag.match(/content\s*=\s*["']([^"']+)["']/i);
    if (content) return content[1].replace(/&amp;/g, '&');
  }
  return null;
}

// Returns { image: Buffer, link: the pin's address } for a Pinterest link, or throws LinkError.
async function imageFromLink(link) {
  const url = parse(link);
  if (!url || !isPinterestPage(url)) throw new LinkError(NOT_PINTEREST);
  try {
    const page = await fetchChecked(url, isPinterestPage);
    const html = (await readLimited(page.res, PAGE_LIMIT)).toString('utf8');
    const address = ogImage(html);
    const imageUrl = address ? parse(address) : null;
    if (!imageUrl || !isPinterestImage(imageUrl)) throw new LinkError(NO_IMAGE);
    const image = await fetchChecked(imageUrl, isPinterestImage);
    const bytes = await readLimited(image.res, IMAGE_LIMIT);
    // Keep the pin's own address, without what came after "?" (tracking).
    const pin = new URL(page.url.href);
    pin.search = '';
    pin.hash = '';
    return { image: bytes, link: pin.href };
  } catch (error) {
    if (error instanceof LinkError) throw error;
    console.error(`A Pinterest link could not be read: ${error.name}`);
    throw new LinkError(NO_IMAGE);
  }
}

// The parts the tests replace, so they never reach Pinterest.
const remote = { imageFromLink };

module.exports = { LinkError, remote, isPinterestLink, ogImage, NOT_PINTEREST };

<?php declare(strict_types=1);

/*
 * You need to get a key and generate a token by visiting this website (And you
 * need to be logged in with the correct account):
 *
 * https://trello.com/app-key
 */
const TRELLO_KEY = '@YOUR_TRELLO_API_KEY@';
const TRELLO_TOKEN = '@YOUR_TRELLO_API_TOKEN@';

/*
 * To find the trello list id, the easiest way is to look up your Trello board,
 * create the list you want to use, add a card, click on the card and add
 * ".json" to the url in the top you can then search for idList" - string
 * behind that is the list_id below.
 */
const TRELLO_LIST_ID = '@YOUR_TRELLO_LIST_ID@';

/*
 * POST values accepted:
 *
 *   name:        The name of the Trello card.
 *   desc:        The Markdown text of the card.
 *   label_id:    An optional label to attach to the card.
 *   cover_file:  The file form field indicating which file should be used as
 *                the cover.
 *   $name:       Any field $name which contains a valid file is added as an
 *                attachment to the card.
 */

if (empty($_POST['name']) || empty($_POST['desc'])) {
    http_response_code(400);
    exit('insufficient data');
}

$label_id = $_POST['label_id'] ?? null;

if ($label_id !== null && !preg_match('/^[0-9a-fA-F]{24}$/', $label_id)) {
    http_response_code(400);
    exit('invalid label_id');
}

$identifier = uniqid();
$name = $_POST['name'].' ['.$identifier.']';
$desc = $_POST['desc'];

$attachments = [];

foreach ($_FILES as $file) {
    if ($file['error'] !== UPLOAD_ERR_OK) {
        http_response_code(400);
        exit('upload of attachment failed');
    }

    if (!is_uploaded_file($file['tmp_name'])) {
        http_response_code(400);
        exit('upload of '.$file['name'].' failed');
    }

    switch ($content_type = mime_content_type($file['tmp_name'])) {
        case 'image/png':
        case 'image/jpeg':
        case 'image/gif':
            if ($file['type'] !== $content_type) {
                http_response_code(400);
                exit('wrong type '.$content_type.' for '.$file['name']);
            }
            break;
        default:
            http_response_code(403);
            exit('mime type '.$content_type.' is not allowed');
    }

    $attachments['Image-'.$identifier] = curl_file_create(
        $file['tmp_name'],
        $file['type'],
        $file['name']
    );
}

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'https://api.trello.com/1/cards');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FAILONERROR, true);

curl_setopt($ch, CURLOPT_POSTFIELDS, [
    'token' => TRELLO_TOKEN,
    'key' => TRELLO_KEY,
    'idList' => TRELLO_LIST_ID,
    'name' => $name,
    'desc' => $desc,
    'pos' => 'top',
]);

if (curl_exec($ch) === false) {
    http_response_code(502);
    curl_close($ch);
    exit('unable to create card');
}

$url = 'https://api.trello.com/1/lists/'.TRELLO_LIST_ID.'/cards';
curl_setopt($ch, CURLOPT_URL, $url.'?'.http_build_query([
    'token' => TRELLO_TOKEN,
    'key' => TRELLO_KEY,
]));
curl_setopt($ch, CURLOPT_HTTPGET, true);

if (($response = curl_exec($ch)) === false) {
    http_response_code(502);
    curl_close($ch);
    exit('unable to determine card ID');
}

if (($cards = json_decode($response, true)) === null) {
    http_response_code(502);
    curl_close($ch);
    exit('unable to decode card ID');
}

$card_id = null;

foreach ($cards as $card) {
    if (strpos($card['name'], $identifier) !== false) {
        $card_id = $card['id'];
    }
}

if ($card_id === null) {
    http_response_code(502);
    curl_close($ch);
    exit('unable to find card with identifier '.$identifier);
}

if (!preg_match('/^[0-9a-fA-F]{24}$/', $card_id)) {
    http_response_code(502);
    curl_close($ch);
    exit('unable to find valid card_id with identifier '.$identifier);
}

if ($label_id !== null) {
    $url = 'https://api.trello.com/1/cards/'.$card_id.'/idLabels';
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, [
        'token' => TRELLO_TOKEN,
        'key' => TRELLO_KEY,
        'value' => $label_id,
    ]);

    if (curl_exec($ch) === false) {
        $msg = 'Unable to attach label '.$label_id.' to card '.$card_id.'.';
        trigger_error($msg, E_USER_WARNING);
    }
}

foreach ($attachments as $name => $file) {
    $url = 'https://api.trello.com/1/cards/'.$card_id.'/attachments';
    $is_cover = $name === ($_POST['cover_file'] ?? null);
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, [
        'token' => TRELLO_TOKEN,
        'key' => TRELLO_KEY,
        'name' => $name,
        'setCover' => $is_cover,
        'file' => $file,
    ]);

    if (curl_exec($ch) === false) {
        http_response_code(502);
        curl_close($ch);
        exit('unable to attach file '.$name.' to card');
    }
}

http_response_code(200);
exit('OK');

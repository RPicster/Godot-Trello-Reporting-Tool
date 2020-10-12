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
 *   cover:       An optional image file to be used as the cover of the card.
 *   attachments: A list of files to attach to the card.
 */

/**
 * Convert a given file upload into a CURLFile for submission with curl_exec()
 *
 * This is basically just a helper to validate the file upload and it stops
 * execution of the script if there are any errors, so the value returned will
 * *always* be valid.
 *
 * @param $file          The file array to handle coming from $_FILES
 * @param $image_only    Whether to only allow images
 * @param $allow_unknown Whether to trust the MIME type provided by uploader
 */
function upload2curl(
    array &$file,
    bool $image_only = false,
    bool $allow_unknown = false
): CURLFile {
    if ($file['error'] !== UPLOAD_ERR_OK) {
        http_response_code(400);
        exit('upload of attachment '.$file['name'].' failed');
    }

    if (!is_uploaded_file($file['tmp_name'])) {
        http_response_code(400);
        exit('refused possible file upload attack for '.$file['name']);
    }

    if ($allow_unknown) {
        $filetype = $file['type'];
    } else {
        $filetype = mime_content_type($file['tmp_name']);
    }

    if ($image_only) {
        switch ($filetype) {
            case 'image/png':  $suffix = 'png'; break;
            case 'image/jpeg': $suffix = 'jpg'; break;
            case 'image/gif':  $suffix = 'gif'; break;
            default:
                http_response_code(403);
                exit('type '.$filetype.' is not allowed for '.$file['name']);
        }
    } else {
        $suffix = pathinfo($file['name'])['extension'] ?? null;
    }

    if ($file['type'] !== $filetype) {
        http_response_code(400);
        exit('wrong type '.$filetype.' for '.$file['name']);
    }

    $name = $file['name'];

    if (!preg_match('/^[a-zA-Z0-9][a-zA-Z0-9_-]*\\.[a-zA-Z0-9]+$/', $name)) {
        $name = uniqid().($suffix !== null ? '.'.$suffix : '');
    }

    return curl_file_create($file['tmp_name'], $file['type'], $name);
}

if (empty($_POST['name']) || empty($_POST['desc'])) {
    http_response_code(400);
    exit('insufficient data');
}

if (!is_string($_POST['name']) || !is_string($_POST['desc'])) {
    http_response_code(400);
    exit('invalid types used in submitted data');
}

$label_id = $_POST['label_id'] ?? null;

if ($label_id !== null && !preg_match('/^[0-9a-fA-F]{24}$/', $label_id)) {
    http_response_code(400);
    exit('invalid label_id');
}

$identifier = uniqid();
$card_name = $_POST['name'].' ['.$identifier.']';
$card_desc = $_POST['desc'];

$cover = null;
if (is_array($_FILES['cover'] ?? null)) {
    $cover = upload2curl($_FILES['cover'], true);
}

$attachments = [];

if (is_array($_FILES['attachments'] ?? null)) {
    if (is_array($_FILES['attachments']['name'])) {
        foreach ($_FILES['attachments']['name'] as $index => $name) {
            $file = [
                'name' => $name,
                'type' => $_FILES['attachments']['type'][$index],
                'error' => $_FILES['attachments']['error'][$index],
                'tmp_name' => $_FILES['attachments']['tmp_name'][$index],
            ];

            $attachments[] = upload2curl($file);
        }
    } else {
        $attachments[] = upload2curl($_FILES['attachments']);
    }
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
    'name' => $card_name,
    'desc' => $card_desc,
    'pos' => 'top',
]);

if (($card = curl_exec($ch)) === false) {
    http_response_code(502);
    curl_close($ch);
    exit('unable to create card');
}

$card = json_decode($card, true);

if ($card === null || !array_key_exists('id', $card)) {
    http_response_code(502);
    curl_close($ch);
    exit('unable to find card identifier');
}

$card_id = $card['id'];

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

$url = 'https://api.trello.com/1/cards/'.$card_id.'/attachments';
curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_POST, true);

if ($cover !== null) {
    curl_setopt($ch, CURLOPT_POSTFIELDS, [
        'token' => TRELLO_TOKEN,
        'key' => TRELLO_KEY,
        'setCover' => true,
        'file' => $cover,
    ]);

    if (curl_exec($ch) === false) {
        http_response_code(502);
        curl_close($ch);
        exit('unable to add cover to card');
    }
}

foreach ($attachments as $idx => $file) {
    curl_setopt($ch, CURLOPT_POSTFIELDS, [
        'token' => TRELLO_TOKEN,
        'key' => TRELLO_KEY,
        'file' => $file,
    ]);

    if (curl_exec($ch) === false) {
        http_response_code(502);
        curl_close($ch);
        exit('unable to upload attachment '.($idx + 1).' to card');
    }
}

http_response_code(200);
exit('OK');

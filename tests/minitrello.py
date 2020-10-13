#!/usr/bin/env nix-shell
#!nix-shell -p python3Packages.flask -p python3 -i python --argstr # noqa
import re
from hashlib import sha256
from mmap import mmap, PROT_READ
from uuid import uuid4
from datetime import date as date_, datetime
from functools import wraps
from typing import cast, Callable, TypeVar, Any, Optional, \
                   Dict, NamedTuple, List
from flask import Flask, request, jsonify

T = TypeVar('T')
app = Flask('Trello')


class Card(NamedTuple):
    id: str
    address: Optional[str] = None
    badges: Any = {}
    checkItemStates: List[str] = []
    closed: bool = False
    coordinates: Optional[str] = None
    creationMethod: Optional[str] = None
    dateLastActivity: datetime = datetime.now()
    desc: str = ''
    descData: Any = {}
    due: Optional[datetime] = None
    dueReminder: Optional[str] = None
    email: str = ''
    idBoard: str = ''
    idChecklists: List[str] = []
    idLabels: List[str] = []
    idList: str = ''
    idMembers: List[str] = []
    idMembersVoted: List[str] = []
    idShort: int = 0
    idAttachmentCover: str = ''
    labels: List[str] = []
    limits: Any = {}
    locationName: Optional[str] = None
    manualCoverAttachment: bool = False
    name: str = ''
    pos: float = 0.0
    shortLink: str = ''
    shortUrl: str = ''
    subscribed: bool = False
    url: str = ''
    cover: Any = {}


class Attachment(NamedTuple):
    id: str
    bytes: Optional[int]
    date: date_ = date_.today()
    edgeColor: Optional[str] = None
    idMember: str = ''
    isUpload: bool = False
    mimeType: str = ''
    name: str = ''
    previews: List[str] = []
    url: str = ''
    pos: int = 0

    # Extra field, not in Trello responses.
    chksum: Optional[str] = None


def is_valid_arg(name, regex):
    val = request.values.get(name)
    return val is not None and re.match(regex, val) is not None


def trello_api_call(f: Callable[..., T]) -> Callable[..., T]:
    @wraps(f)
    def _validate_api_call(*args: Any, **kwargs: Any) -> T:
        if is_valid_arg('key', '^[0-9a-fA-F]{32}$') and \
           is_valid_arg('token', '^[0-9a-fA-F]{64}$'):
            return f(*args, **kwargs)
        return app.make_response(('invalid key', 401))
    return _validate_api_call


trello_lists: Dict[str, List[Card]] = {}
trello_attachments: Dict[str, List[Attachment]] = {}


@app.route('/1/cards', methods=['POST'])
@trello_api_call
def create_card() -> Any:
    idlist = request.values.get('idList')
    if idlist is None:
        return app.make_response(('idList required', 400))

    if not is_valid_arg('idList', '^[0-9a-fA-F]{24}$'):
        return app.make_response(('invalid idList value', 400))

    if idlist not in trello_lists:
        trello_lists[idlist] = []

    pos = request.values.get('pos', 'bottom')
    if pos == 'bottom':
        highest = max(trello_lists[idlist], default=None, key=lambda c: c.pos)
        newpos = 1000.0 if highest is None else highest.pos + 1.0
    elif pos == 'top':
        lowest = min(trello_lists[idlist], default=None, key=lambda c: c.pos)
        newpos = 10.0 if lowest is None else lowest.pos / 2.0
    else:
        newpos = float(pos)

    newcard = Card(
        uuid4().hex[:24],
        pos=newpos,
        address=request.values.get('address'),
        coordinates=request.values.get('coordinates'),
        desc=request.values.get('desc', ''),
        due=request.values.get('due'),
        dueReminder=request.values.get('dueComplete'),
        idLabels=request.values.get('idLabels', []),
        idMembers=request.values.get('idMembers', []),
        locationName=request.values.get('locationName'),
        name=request.values.get('name', ''),
        url=request.values.get('urlSource', ''),
    )

    trello_lists[idlist].append(newcard)
    trello_lists[idlist].sort(key=lambda c: c.pos)

    return jsonify(newcard._asdict())


@app.route('/1/cards/<cardid>/idLabels', methods=['POST'])
@trello_api_call
def add_label(cardid: str) -> Any:
    if re.match('^[0-9a-fA-F]{24}$', cardid) is None:
        return app.make_response(('invalid cardid value', 400))

    newlabel = request.values.get('value')
    if newlabel is not None:
        for cards in trello_lists.values():
            for card in cards:
                if card.id == cardid.lower():
                    card.idLabels.append(newlabel)
                    return jsonify(card.idLabels)

    return app.make_response(('invalid value for value', 400))


@app.route('/1/cards/<cardid>/attachments', methods=['POST'])
@trello_api_call
def add_attachment(cardid: str) -> Any:
    if re.match('^[0-9a-fA-F]{24}$', cardid) is None:
        return app.make_response(('invalid cardid value', 400))

    mimetype = ''
    filename = ''
    filesize = None
    chksum = None
    if 'file' in request.files:
        reqfile = request.files['file']
        with mmap(reqfile.fileno(), 0, prot=PROT_READ) as data:
            filesize = len(data)
            chksum = sha256(cast(bytes, data)).hexdigest()
        mimetype = reqfile.mimetype
        filename = reqfile.filename

    if cardid not in trello_attachments:
        trello_attachments[cardid] = []

    pos = len(trello_attachments[cardid])
    newattachment = Attachment(
        uuid4().hex[:24],
        bytes=filesize,
        chksum=chksum,
        pos=pos,
        mimeType=request.values.get('mimeType', mimetype),
        name=request.values.get('name', filename),
    )

    trello_attachments[cardid].append(newattachment)
    adict = newattachment._asdict()
    del adict['chksum']
    return jsonify(adict)


@app.route('/1/lists/<listid>/cards', methods=['GET'])
@trello_api_call
def list_cards(listid: str) -> Any:
    return jsonify([c._asdict() for c in trello_lists.get(listid, [])])


@app.route('/__get_state', methods=['GET'])
def get_state() -> Any:

    return jsonify({
        'lists': {
            listid: list(map(lambda a: a._asdict(), cards))
            for listid, cards in trello_lists.items()
        },
        'attachments': {
            cardid: list(map(lambda a: a._asdict(), attachments))
            for cardid, attachments in trello_attachments.items()
        },
    })


if __name__ == '__main__':
    app.run()

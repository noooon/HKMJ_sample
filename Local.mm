//
//  Local.mm
//  HKMahjong
//
//  Created by Paul on 03/05/2013.
//
//

#import "Local.h"
#import "GameCenter.h"
#import "HKMJEvents.h"
#import "LocalClient.h"
#import "RemoteClient.h"
#import "StartRoundLayer.h"

Local* Local::_instance = nullptr;

Local::Local()
: m_clients {nullptr, nullptr, nullptr, nullptr}
, _dealer(nullptr)
, m_gameView(nullptr)
{
	m_gameView = new GameView;
	m_gameView->frameTickDelegate = MakeDelegate(this, &Local::tick);
	
	// Set up event listeners
	EventManager::get()->addListener(MakeDelegate(this, &Local::addCardToFlowersEvent), AddCardToFlowersEvent::sk_eventType);
	EventManager::get()->addListener(MakeDelegate(this, &Local::addCardToHandEvent), AddCardToHandEvent::sk_eventType);
	EventManager::get()->addListener(MakeDelegate(this, &Local::initNewRoundEvent), InitNewRoundEvent::sk_eventType);
	EventManager::get()->addListener(MakeDelegate(this, &Local::wellVisionAdd), PlayerDiscardEvent::sk_eventType);
	EventManager::get()->addListener(MakeDelegate(this, &Local::resetVision), PlayerDeclaresWinEvent::sk_eventType);
	EventManager::get()->addListener(MakeDelegate(this, &Local::updateKongVision), PlayerFormsKongEvent::sk_eventType);
	EventManager::get()->addListener(MakeDelegate(this, &Local::updateMeldVision), PlayerFormsMeldEvent::sk_eventType);
}

Local::~Local()
{
	for (auto mClient : m_clients)
	{
		delete mClient;
		mClient = nullptr;
	}
	
	delete _dealer;
	_dealer = nullptr;
	
	delete m_gameView;
	m_gameView = nullptr;
}

void Local::addCardToHandEvent(EventListenerDelegateParameter event)
{
	dlog("    [%s] is processing event.\n", __funcname__);
	auto evt = reinterpret_cast<AddCardToHandEvent *>(event->getDataPtr().get());
	m_gameView->setMustDiscardIcon(evt->_playerID);
}

void Local::addCardToFlowersEvent(EventListenerDelegateParameter event)
{
	dlog("    [%s] is processing event.\n", __funcname__);
	auto evt = reinterpret_cast<AddCardToFlowersEvent *>(event->getDataPtr().get());
	_playerVision._playerFlowers[evt->_playerID].push_back(Deck::get()->getCardWithID(evt->_receivedFlowerID));
	m_gameView->queueRedrawPlayer(evt->_playerID);
}

/**
 Do initialisation.
 */
void Local::init(const bool isHost, const std::array<bool, 4> &isLocalClient, const std::array<bool, 4> &isAIClient, NSArray *playerIDs)
{
	dlog("[%s]\n", __funcname__);

	// Create the dealer.
	if (isHost)
	{
		dlog("Creating a LocalDealer\n");
		_dealer = new LocalDealer;
	}
	else
	{
		dlog("Creating a RemoteDealer\n");
		_dealer = new RemoteDealer;
	}
	
	for (unsigned int i = 0; i < 4; ++i)
	{
		NSString *clientIDString = (i < playerIDs.count) ? playerIDs[i] : @"";
		
		if (isLocalClient[i])
		{
			if (isAIClient[i])
			{
				dlog("Creating an AIClient with ID: %s\n", clientIDString.UTF8String);
				m_clients[i] = new AIClient(clientIDString, i);
			}
			else
			{
				dlog("Creating a local HumanClient with ID: %s\n", clientIDString.UTF8String);
				// Should only create this once if this local device isn't the Host
				//TODO: Probably allocate the GameView here and attach it to the HumanClient.
				m_clients[i] = new HumanClient(clientIDString, i);
				_localHumanPlayerID = i;
			}
		}
		else
		{
			dlog("Creating a RemoteClient with ID: %s\n", clientIDString.UTF8String);
			m_clients[i] = new RemoteClient(clientIDString, i);
		}
	}
	
	// Grab player names from Game Center
	if (playerIDs != nil)
	{
		[GKPlayer loadPlayersForIdentifiers:playerIDs withCompletionHandler:^(NSArray *players, NSError *error)
		 {
			 if (error)
			 {
				 dNSLog(@"Failed to retrieve match GKPlayer data for reason: %@ - %@", error.localizedFailureReason, error.localizedDescription);
				 return;
			 }
			 
			 dlog("GKPlayers retrieved\n");
			 for (unsigned int i = 0; i < players.count; ++i)
			 {
				 if (m_clients[i] != nullptr)
				 {
					 NSString *name = [players[i] displayName];
					 
					 if ([name isEqualToString:@"Me"])
					 {
						 name = [players[i] alias];
					 }
					 
					 // Remove any non alphanumeric characters because it futzes with CString text rendering
					 NSCharacterSet *charactersToRemove = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
					 std::string displayName = [name stringByTrimmingCharactersInSet:charactersToRemove].UTF8String;
					 m_clients[i]->_playerName = displayName;
					 dlog("Setting player#%d (%s) name as %s\n", i, [players[i] playerID].UTF8String, [players[i] displayName].UTF8String);
					 // Queue as a forwarded event, since every client will excute this anyway.
					 EventManager::get()->queueForwardedEvent(queueEventMacro(PlayerRenamedEvent, displayName, i)); //HACK: Not sure if there's a way to tie the GKPlayer data to playerID, so I'm making an assumption that Human players will always be initialised in order first, then the AI players.
				 }
			 }
		 }];
	}
	
	m_gameView->init(_localHumanPlayerID);
}

/**
 Helper for 'New Match', 'Load Match', and 'New Multiplayer Match' menu options. Resets application state. Also figues 
 out which players are local and which are AI players based on the playerID strings.
 */
void Local::initGame(const bool localIsHost, NSArray *playerIDs)
{
	dlog("[%s]\n", __funcname__);
	
	//TODO: Could probably move this to Local::init()
	std::array<bool, 4> isLocal = { { true, true, true, true } };
	std::array<bool, 4> isAI = { { false, true, true, true } };
	
	// Pass nil for a Single-player game.
	if (playerIDs != nil)
	{		
		for (unsigned int i = 0; i < 4; ++i)
		{
			// Is there a ID string for this player? This indicates a real game center account linked to it.
			if (i < playerIDs.count)
			{
				isAI[i] = false;
				isLocal[i] = ([GKLocalPlayer localPlayer].playerID == playerIDs[i]) ? true : false;
			}
			else
			{
				isAI[i] = true;
				isLocal[i] = (localIsHost) ? true : false; // A local host will manage the AI clients, otherwise it's not this client's concern.
			}
		}
	}
	
	Deck::dealloc(); // Deck needs to be deallocated, so that the cards are all re-added to the GameView.
	Local::dealloc(); // Force deallocation before reallocating.
	
	Local::get()->init(localIsHost, isLocal, isAI, playerIDs);
}

void Local::initNewRoundEvent(EventListenerDelegateParameter event)
{
	dlog("    [%s] is processing event.\n", __funcname__);
	auto evt = reinterpret_cast<InitNewRoundEvent *>(event->getDataPtr().get());
	
	// GameView bits, possibly move this to a GameView method.
	Local::get()->m_gameView->clearAnimationList(); // This should solve problems where animations would continue to play after when a new game is beginning.
	
	for (int i = 0; i < 4; ++i)
	{
		Local::get()->m_gameView->setPlayerNameText(i, Local::get()->m_clients[i]->_playerName);
	}
	
	resetVision(nullptr);
	
	_dealer->initNewRound(evt->_newDealerID);
	
	StartRoundLayer::get()->remove(false); //TODO: Put transition back in. Not in at the moment because the initial deal animation will play before the start screen has finished transitioning out.
}

void Local::resetVision(EventListenerDelegateParameter event)
{
	for (auto& meldStack : _playerVision._playerMelds)
	{
		meldStack.clear();
	}
	
	for (auto &flowerStack : _playerVision._playerFlowers)
	{
		flowerStack.clear();
	}
	
	_playerVision._well.clear();
}

/**
 */
void Local::tick()
{
	for (int i = 0; i < 4; ++i)
	{
		//TODO: In the case of pass-around multiplayer, figure out which client we should be handling input for.
		m_clients[i]->tick();
	}
}

void Local::updateMeldVisionHelper(const card_t::CardInt &lastDiscardID, const MeldIDStack &meldIDStack, const int playerID)
{
	int insertPosition = -1; // The position the meld should be added into the player's hand. This is pretty much just used for forming a Kong with an existing Pong.
	
	// Cards not removed from hand, probably forming a Kong with an existing Pong.
	if (meldIDStack.size() == 4)
	{
		melds_t &playerMelds = _playerVision._playerMelds[playerID];
		
		// Find the Pong that matches this Kong in player vision.
		for (int i = 0; i < playerMelds.size(); ++i)
		{
			auto &tmeld = playerMelds[i];
			card_t *meldFirstCard = Deck::get()->getCardWithID(meldIDStack[0]);
			int removeCount = 0;
			
			// Match the value of each card in the existing meld to the incoming Kong.
			for (int j = 0; j < tmeld.size(); ++j)
			{
				if (tmeld[j]->value != meldFirstCard->value)
				{
					break;
				}
				
				++removeCount;
			}
			
			// Found the matching pong
			if (removeCount == 3)
			{
				// Remove the pong, so it will be added again as a kong
				playerMelds.erase(i);
				insertPosition = i;
				break;
			}
		}
	}

	meld_t addMeld;
	
	// Retrieve card objects with ID.
	for (int card = 0; card < meldIDStack.size(); ++card)
	{
		auto cardID = meldIDStack[card];
		addMeld.push_back(Deck::get()->getCardWithID(cardID));
	}
	
	// Add the cards to player meld vision.
	if (insertPosition == -1)
	{
		_playerVision._playerMelds[playerID].push_back(addMeld);
	}
	else
	{
		_playerVision._playerMelds[playerID].insert(insertPosition, addMeld);
	}
	
	// This meld was formed by stealing card from the well, therefore that card needs to be removed from the well.
	if (lastDiscardID != -1)
	{
		dassert(lastDiscardID == _playerVision._well.back()->m_id, "Attempting to remove card from vision, mismatched ID!");
		_playerVision._well.pop_back();
	}
}

/**
 */
//TODO: Refactor, this is essentially the same as updateMeldVision, only the event type is different.
void Local::updateKongVision(EventListenerDelegateParameter event)
{
	dlog("[%s] is processing event.\n", __funcname__);
	auto evt = reinterpret_cast<PlayerFormsKongEvent *>(event->getDataPtr().get());
	updateMeldVisionHelper(evt->_lastDiscardID, evt->_meldIDStack, evt->_playerID);
}

/**
 */
void Local::updateMeldVision(EventListenerDelegateParameter event)
{
	dlog("[%s] is processing event.\n", __funcname__);
	auto evt = reinterpret_cast<PlayerFormsMeldEvent *>(event->getDataPtr().get());
	updateMeldVisionHelper(evt->_lastDiscardID, evt->_meldIDStack, evt->_playerID);
}

/**
 Handles discard event, where a card will be added to the well.
 */
void Local::wellVisionAdd(EventListenerDelegateParameter event)
{
	dlog("[%s] is processing event.\n", __funcname__);
	auto evt = reinterpret_cast<PlayerDiscardEvent *>(event->getDataPtr().get());
	
	// Get card data from deck using cardID.
	card_t* card = Deck::get()->getCardWithID(evt->_cardID);
	
	// Add it to the well.
	_playerVision._well.push_back(card);
}

void Local::dealloc()
{
	delete _instance;
	_instance = nullptr;
}

Local* Local::get()
{
	if (_instance == nullptr)
	{
		_instance = new Local;
	}
	
	return _instance;
}

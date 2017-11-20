//
//  Local.h
//  HKMahjong
//
//  Created by Paul on 03/05/2013.
//
//

#import "card.h"
#import "Client.h"
#import "GameView.h"
#import "Dealer.h"

#define USE_FIXED_SEED 0

struct RecordStats {
	MeldsIDStack _bestHandIDs;
	int best_match;
	int best_round;
	int current_winning_streak;
	int longest_winning_streak;
	int _lifetimePointsScored;
	int matches_played;
	int matches_won;
	int _roundsPlayed; // This counds the number of rounds played including rounds that resulted in stalemate.
	int rounds_won;
	
	RecordStats()
	{
		memset(this, 0, sizeof(*this));
	}
};

/**
 Maintains local global application state. Should include current match state such as fog of war, Player names, and game
 score.
 */
class Local {
public:
	/**
	 Cards that clients have vision of.
	 */
	struct PlayerVision {
		std::array<melds_t, k_numPlayers> _playerMelds;
		std::array<flower_t, k_numPlayers> _playerFlowers;
		Stack<card_t*, k_maxcards> _well;
	};
	
	static void dealloc();
	static Local* get();
	static void initGame(const bool localIsHost, NSArray *playerIDs);
	
	IClient* m_clients[4];
	IDealer* _dealer;
	DialogLayer _dialog;
	GameView *m_gameView;
	int _localHumanPlayerID;
	PlayerVision _playerVision;
	RecordStats _recordStats;
	
	void init(const bool isHost, const std::array<bool, 4> &isLocalClient, const std::array<bool, 4> &isAIClient, NSArray *playerIDs);
	void tick();
	
private:
	static Local* _instance;
	
	Local();
	~Local();
	
	Local(Local const&) = delete;
	void operator = (Local const &) = delete;
	
	void addCardToHandEvent(EventListenerDelegateParameter event);
	void addCardToFlowersEvent(EventListenerDelegateParameter event);
	void initNewRoundEvent(EventListenerDelegateParameter event);
	void resetVision(EventListenerDelegateParameter event);
	void saveGameState(EventListenerDelegateParameter event);
	void updateKongVision(EventListenerDelegateParameter event);
	void updateMeldVision(EventListenerDelegateParameter event);
	void updateMeldVisionHelper(const card_t::CardInt& lastDiscardID, const MeldIDStack& meldIDStack, const int playerID);
	void wellVisionAdd(EventListenerDelegateParameter event);
};
